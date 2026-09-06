import AppKit
import Foundation
import Darwin

enum QuickChatKnowledgeError: String, Error, LocalizedError {
    case permission = "Choose the Knowledge Folder again. Access is unavailable."
    case invalid = "Use relative subfolder names without dots or parent traversal."
    case unavailable = "The Knowledge Folder is unavailable. No excerpts were sent."
    var errorDescription: String? { rawValue }
}

/// A bounded, descriptor-relative reader. Directory descriptors anchor traversal;
/// O_NOFOLLOW rejects symlinks at every level, and hard-linked files are skipped.
enum QuickChatKnowledgeReader {
    static let maximumFiles = 500
    static let maximumEntries = 2_000
    static let maximumFileBytes = 256 * 1024
    static let maximumResults = 4
    static let excerptCharacters = 1_000

    static func subfolders(_ value: String) throws -> [[String]] {
        try value.split(whereSeparator: \.isNewline).map { line in
            let text = String(line).trimmingCharacters(in: .whitespaces)
            let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") && !$0.contains("\0") && !$0.contains("\\") }) else {
                throw QuickChatKnowledgeError.invalid
            }
            return parts
        }
    }

    private static func isPrefix(_ prefix: [String], of path: [String]) -> Bool {
        path.count >= prefix.count && Array(path.prefix(prefix.count)) == prefix
    }

    static func search(root: URL, question: String, included: String = "", excluded: String = "") throws -> [QuickChatCitation] {
        let includes = try subfolders(included), excludes = try subfolders(excluded)
        let stopWords: Set<String> = ["the", "this", "that", "what", "which", "with", "from", "about", "please", "explain", "have", "does", "are", "and", "for", "can"]
        let terms = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count >= 3 && !stopWords.contains(String($0)) }.prefix(32).map(String.init))
        guard !terms.isEmpty else { return [] }
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw QuickChatKnowledgeError.unavailable }
        defer { close(rootFD) }
        var visited = 0, readFiles = 0
        var totalBytes = 0
        let deadline = Date().addingTimeInterval(3)
        var ranked: [(Int, QuickChatCitation)] = []

        func walk(_ directoryFD: Int32, parts: [String]) throws {
            try Task.checkCancellation()
            guard parts.count <= 12, visited < maximumEntries, readFiles < maximumFiles,
                  !excludes.contains(where: { isPrefix($0, of: parts) }) else { return }
            guard let directory = fdopendir(dup(directoryFD)) else { return }
            defer { closedir(directory) }
            while let entry = readdir(directory), visited < maximumEntries, readFiles < maximumFiles,
                  totalBytes < 16 * 1024 * 1024, Date() < deadline {
                try Task.checkCancellation()
                visited += 1
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                guard !name.hasPrefix("."), !name.contains("/"), !name.contains("\\") else { continue }
                let path = parts + [name]
                guard !excludes.contains(where: { isPrefix($0, of: path) }) else { continue }
                var metadata = stat()
                guard fstatat(directoryFD, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                      metadata.st_mode & S_IFMT != S_IFLNK,
                      metadata.st_flags & UInt32(SF_DATALESS | UF_HIDDEN) == 0 else { continue }
                let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { continue }
                defer { close(fd) }
                var before = stat()
                guard fstat(fd, &before) == 0, before.st_ino == metadata.st_ino,
                      before.st_dev == metadata.st_dev else { continue }
                if before.st_mode & S_IFMT == S_IFDIR {
                    if includes.isEmpty || includes.contains(where: { isPrefix($0, of: path) || isPrefix(path, of: $0) }) {
                        try walk(fd, parts: path)
                    }
                    continue
                }
                guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
                      before.st_size > 0, before.st_size <= maximumFileBytes,
                      includes.isEmpty || includes.contains(where: { isPrefix($0, of: path) }) else { continue }
                let lower = name.lowercased(), ext = (lower as NSString).pathExtension
                guard ["md", "markdown", "txt"].contains(ext),
                      !["agents.md", "claude.md", "kimi.md"].contains(lower),
                      !["secret", "credential", "password", "token", "auth."].contains(where: lower.contains) else { continue }
                // Never materialize an offline iCloud placeholder or follow an alias.
                let url = root.appendingPathComponent(path.joined(separator: "/"))
                let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                guard values?.isAliasFile != true,
                      values?.isUbiquitousItem != true || values?.ubiquitousItemDownloadingStatus == .current else { continue }
                var buffer = [UInt8](repeating: 0, count: Int(before.st_size) + 1)
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                var after = stat()
                guard count == before.st_size, fstat(fd, &after) == 0,
                      before.st_ino == after.st_ino, before.st_size == after.st_size,
                      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                      let text = String(bytes: buffer.prefix(count), encoding: .utf8), !text.contains("\0") else { continue }
                readFiles += 1
                totalBytes += count
                let folded = text.lowercased(), pathText = path.joined(separator: "/").lowercased()
                let matches = terms.filter { folded.contains($0) || pathText.contains($0) }
                guard !matches.isEmpty else { continue }
                let score = matches.count + terms.filter { pathText.contains($0) }.count * 3
                let lines = text.components(separatedBy: .newlines)
                let line = lines.firstIndex(where: { line in terms.contains(where: line.lowercased().contains) }) ?? 0
                let excerpt = String(lines.dropFirst(max(0, line - 1)).prefix(20).joined(separator: "\n").prefix(excerptCharacters))
                let citation = QuickChatCitation(id: "", relativePath: path.joined(separator: "/"), excerpt: excerpt,
                    modifiedAt: Date(timeIntervalSince1970: TimeInterval(after.st_mtimespec.tv_sec)))
                ranked.append((score, citation))
                ranked.sort { $0.0 == $1.0 ? $0.1.relativePath < $1.1.relativePath : $0.0 > $1.0 }
                if ranked.count > maximumResults { ranked.removeLast() }
            }
        }
        try walk(rootFD, parts: [])
        return ranked.enumerated().map { index, result in
            .init(id: "K\(index + 1)", relativePath: result.1.relativePath,
                  excerpt: result.1.excerpt, modifiedAt: result.1.modifiedAt)
        }
    }
}

struct BookmarkedQuickChatKnowledge: QuickChatKnowledgeRetrieving {
    let bookmark: Data
    let included: String
    let excluded: String
    func search(question: String) async throws -> [QuickChatCitation] {
        let task = Task.detached(priority: .utility) {
            var stale = false
            let root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, root.startAccessingSecurityScopedResource() else { throw QuickChatKnowledgeError.permission }
            defer { root.stopAccessingSecurityScopedResource() }
            return try QuickChatKnowledgeReader.search(root: root, question: question, included: included, excluded: excluded)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

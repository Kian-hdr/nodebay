import AppKit
import Foundation
import Darwin

enum QuickNoteError: String, Error, LocalizedError {
    case empty = "Copy some text first."
    case tooLarge = "Quick Notes supports up to 1 MiB of text and 4 MiB of rich clipboard data."
    case storage = "The note could not be saved. Check available disk space and try again."
    case busy = "A note is being saved. Please try again in a moment."
    var errorDescription: String? { rawValue }
}

struct QuickNoteClipboard: Sendable {
    var text: String?
    var html: Data?
    var rtf: Data?
    var fileURLs: [URL] = []
}

enum ShelfPasteRoute: Equatable {
    case files([URL]), downloads([URL]), note, unhandled

    static func decide(_ snapshot: QuickNoteClipboard, notesEnabled: Bool) -> Self {
        if !snapshot.fileURLs.isEmpty { return .files(snapshot.fileURLs) }
        if let text = snapshot.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tokens = text.split(whereSeparator: \.isWhitespace)
            let urls = tokens.compactMap { token -> URL? in
                guard let parts = URLComponents(string: String(token)),
                      ["http", "https", "file"].contains(parts.scheme?.lowercased() ?? ""),
                      parts.user == nil, parts.password == nil,
                      let url = parts.url,
                      url.isFileURL || parts.host?.isEmpty == false else { return nil }
                return url
            }
            if urls.count == tokens.count {
                if urls.allSatisfy(\.isFileURL) { return .files(urls) }
                if urls.allSatisfy({ !$0.isFileURL }) {
                    var seen = Set<URL>()
                    return .downloads(urls.filter { seen.insert($0).inserted })
                }
            }
            return notesEnabled ? .note : .unhandled
        }
        return notesEnabled && (snapshot.html != nil || snapshot.rtf != nil) ? .note : .unhandled
    }
}

struct QuickNoteOptions: Sendable {
    var preferHeading = false
    var preserveRichText = true
    var compactFilename = false
}

struct QuickNoteResult: Sendable {
    let url: URL
    let characterCount: Int
    let representation: String
}

enum QuickNoteText {
    static let maximumTextBytes = 1_048_576
    static let maximumRichBytes = 4_194_304

    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func prepare(_ snapshot: QuickNoteClipboard, rich: Bool) throws -> (String, String) {
        guard (snapshot.text?.utf8.count ?? 0) <= maximumTextBytes else { throw QuickNoteError.tooLarge }
        let plain = snapshot.text.map(normalize)
        if rich && !(plain.map(looksLikeMarkdown) ?? false) {
            if let html = snapshot.html, html.count <= maximumRichBytes, let result = LocalClipboardHTML.markdown(html),
               plain == nil || equivalentText(LocalClipboardHTML.visibleText(html) ?? "", plain!),
               let prepared = try? validated(result, representation: "HTML") {
                return prepared
            }
            if let rtf = snapshot.rtf, rtf.count <= maximumRichBytes, let value = try? NSAttributedString(
                data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
            ), plain == nil || normalize(value.string) == plain {
                var unsupported = false
                var result = ""
                value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
                    if attributes[.attachment] != nil { unsupported = true }
                    let text = (value.string as NSString).substring(with: range)
                    let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
                    if traits.contains(.bold) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result += "**\(text)**"
                    } else if traits.contains(.italic) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result += "*\(text)*"
                    } else { result += text }
                }
                if !unsupported, let prepared = try? validated(normalize(result), representation: "RTF") { return prepared }
            }
        }
        guard let plain else {
            if (snapshot.html?.count ?? 0) > maximumRichBytes || (snapshot.rtf?.count ?? 0) > maximumRichBytes { throw QuickNoteError.tooLarge }
            throw QuickNoteError.empty
        }
        return try validated(plain, representation: "Plain text")
    }

    private static func validated(_ text: String, representation: String) throws -> (String, String) {
        guard text.utf8.count <= maximumTextBytes else { throw QuickNoteError.tooLarge }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickNoteError.empty }
        return (text, representation)
    }

    private static func looksLikeMarkdown(_ text: String) -> Bool {
        text.range(of: "(?m)^( {0,3}#{1,6} |[ \\t]*[-*+] |[ \\t]*[0-9]+[.)] |> ?|```|~~~)|\\*\\*|`|\\[[^\\]]+\\]\\(", options: .regularExpression) != nil
    }

    private static func equivalentText(_ left: String, _ right: String) -> Bool {
        left.split(whereSeparator: \.isWhitespace) == right.split(whereSeparator: \.isWhitespace)
    }

    static func filenameStem(_ text: String, options: QuickNoteOptions, date: Date) -> String {
        // Arbitrary short headings can still be passwords or confidential phrases.
        // Only generic headings are eligible, even when the user opts in.
        let genericHeadings: Set<String> = ["notes", "quick notes", "meeting notes", "ideas", "todo", "checklist", "summary", "plan", "draft", "journal"]
        if options.preferHeading {
            var fence: String?
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    let marker = String(trimmed.prefix(3))
                    if fence == nil { fence = marker } else if fence == marker { fence = nil }
                    continue
                }
                if fence != nil { continue }
                guard let range = trimmed.range(of: "^#{1,6} +", options: .regularExpression) else { continue }
                let heading = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if genericHeadings.contains(heading.lowercased()) { return heading }
                break
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = options.compactFilename ? "yyyyMMdd-HHmmss" : "yyyy-MM-dd HH-mm"
        return "Quick Note \(formatter.string(from: date))"
    }
}

/// Parses a conservative, offline HTML subset. Never uses WebKit or AppKit's
/// HTML importer, which can load remote resources. Malformed/unsupported HTML
/// falls back to the copied plain text, rather than guessing at its meaning.
private final class LocalClipboardHTML: NSObject, XMLParserDelegate {
    var output = ""
    var visible = ""
    var valid = true
    var lists: [(ordered: Bool, index: Int)] = []
    var links: [String] = []
    var preDepth = 0
    var quoteDepth = 0
    var depth = 0
    var nodeCount = 0
    var fence = "```"
    static func parse(_ data: Data) -> LocalClipboardHTML? {
        guard var html = String(data: data, encoding: .utf8), !html.contains("<!") else { return nil }
        html = html.replacingOccurrences(of: "&nbsp;", with: "&#160;")
            .replacingOccurrences(of: "<br\\s*/?>", with: "<br/>", options: .regularExpression)
        let delegate = LocalClipboardHTML()
        // A longer fence cannot be closed by copied code containing backticks.
        while html.contains(delegate.fence) { delegate.fence += "`" }
        let parser = XMLParser(data: Data(("<nodebay>" + html + "</nodebay>").utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.valid else { return nil }
        return delegate
    }
    static func markdown(_ data: Data) -> String? { parse(data)?.output.trimmingCharacters(in: .newlines) }
    static func visibleText(_ data: Data) -> String? { parse(data)?.visible }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard output.utf8.count + string.utf8.count <= QuickNoteText.maximumTextBytes else { valid = false; parser.abortParsing(); return }
        visible += string
        output += quoteDepth > 0 ? string.replacingOccurrences(of: "\n", with: "\n> ") : string
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        nodeCount += 1
        guard depth <= 32, nodeCount <= 50_000, output.utf8.count <= QuickNoteText.maximumTextBytes else { valid = false; parser.abortParsing(); return }
        switch name.lowercased() {
        case "nodebay", "html", "body", "span": break
        case "p", "div": output += "\n\n" + String(repeating: "> ", count: quoteDepth); visible += "\n"
        case "h1", "h2", "h3", "h4", "h5", "h6": output += "\n\n" + String(repeating: "#", count: Int(name.suffix(1)) ?? 1) + " "
        case "br": output += "\n"; visible += "\n"
        case "strong", "b": output += "**"
        case "em", "i": output += "*"
        case "ul": lists.append((false, 0)); output += "\n"
        case "ol":
            // Clipboard attributes are untrusted. Reject pathological counters
            // rather than overflowing while subtracting or incrementing them.
            guard let start = Int(attributes["start"] ?? "1"), (1...1_000_000).contains(start) else {
                valid = false; parser.abortParsing(); return
            }
            lists.append((true, start - 1)); output += "\n"
        case "li":
            guard !lists.isEmpty else { valid = false; return }
            lists[lists.count - 1].index += 1
            let list = lists[lists.count - 1]
            output += "\n" + String(repeating: "  ", count: lists.count - 1) + (list.ordered ? "\(list.index). " : "- ")
            visible += "\n"
        case "blockquote": quoteDepth += 1; output += "\n\n> "; visible += "\n"
        case "pre": preDepth += 1; output += "\n\n\(fence)\n"; visible += "\n"
        case "code": if preDepth == 0 { output += "`" }
        case "a":
            guard let href = attributes["href"], let url = URL(string: href),
                  ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? ""),
                  !href.contains("\n") else { valid = false; return }
            links.append(href.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29"))
            output += "["
        default: valid = false; parser.abortParsing()
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        depth = max(0, depth - 1)
        switch name.lowercased() {
        case "strong", "b": output += "**"
        case "em", "i": output += "*"
        case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6": output += "\n\n"; visible += "\n"
        case "ul", "ol": if !lists.isEmpty { lists.removeLast() }; output += "\n"; visible += "\n"
        case "blockquote": quoteDepth = max(0, quoteDepth - 1); output += "\n"
        case "pre": preDepth = max(0, preDepth - 1); output += "\n\(fence)\n"
        case "code": if preDepth == 0 { output += "`" }
        case "a": if let link = links.popLast() { output += "](\(link))" }
        default: break
        }
    }
}

actor QuickNoteService {
    static let shared = QuickNoteService()
    private let write: @Sendable (FileHandle, Data) throws -> Void
    init(write: @escaping @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }) {
        self.write = write
    }
    /// Completion returns only metadata; the clipboard snapshot and rendered text
    /// are scoped to this operation and are never persisted as diagnostics.
    func create(_ snapshot: QuickNoteClipboard, options: QuickNoteOptions, directory: URL, date: Date = Date()) throws -> QuickNoteResult {
        let (text, representation) = try QuickNoteText.prepare(snapshot, rich: options.preserveRichText)
        let stem = QuickNoteText.filenameStem(text, options: options, date: date)
        let temporary = directory.appendingPathComponent(".nodebay-note-\(UUID()).tmp")
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let descriptor = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
            guard descriptor >= 0 else { throw QuickNoteError.storage }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
            try write(handle, Data(text.utf8))
            try handle.synchronize()
            try handle.close()
            try Task.checkCancellation()
            // Hard-link promotion is atomic and fails with EEXIST rather than
            // replacing a destination created by another process.
            for number in 1...10_000 {
                let suffix = number == 1 ? "" : " \(number)"
                let destination = directory.appendingPathComponent("\(stem)\(suffix).md")
                if link(temporary.path, destination.path) == 0 {
                    return .init(url: destination, characterCount: text.count, representation: representation)
                }
                guard errno == EEXIST else { throw QuickNoteError.storage }
            }
            throw QuickNoteError.storage
        } catch is CancellationError { throw CancellationError() }
        catch { throw QuickNoteError.storage }
    }
}

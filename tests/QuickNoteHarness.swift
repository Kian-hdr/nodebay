import AppKit
import Foundation

@main struct QuickNoteHarness {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nodebay-note-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = QuickNoteService()
        let date = Date(timeIntervalSince1970: 1_788_357_000)
        let samples = [
            "Plain copied text", "# Heading\n\n- First\n- Second\n\n> Quote\n",
            "```swift\nlet x = 1\nprint(x)\n```\n", "## Prompt\nExplain this code without changing it.\n",
            "Claude/Codex prompt: keep this exact wording.\n\n1. Inspect\n2. Test\n",
            "日本語 العربية Deutsch 👩🏽‍💻 🚀\né e\u{301}\n", "See https://youtu.be/example for context.\n",
            "**Bold** *italic* [link](https://example.test) `code`", String(repeating: "line\n", count: 100_000),
        ]
        for sample in samples {
            let result = try await service.create(.init(text: sample), options: .init(), directory: root, date: date)
            let contents = try String(contentsOf: result.url, encoding: .utf8)
            precondition(contents == sample)
            let bytes = try Data(contentsOf: result.url)
            precondition(bytes == Data(sample.utf8))
            precondition(result.url.pathExtension == "md" && result.characterCount == sample.count)
            precondition(!result.url.lastPathComponent.contains("Prompt"))
        }
        let crlf = try QuickNoteText.prepare(.init(text: "a\r\nb\rc\n"), rich: true)
        precondition(crlf.0 == "a\nb\nc\n")
        let a = try await service.create(.init(text: "first"), options: .init(), directory: root, date: date)
        let b = try await service.create(.init(text: "second"), options: .init(), directory: root, date: date)
        precondition(a.url != b.url)
        let original = try String(contentsOf: a.url, encoding: .utf8)
        precondition(original == "first")
        let relaunched = QuickNoteService()
        _ = try await relaunched.create(.init(text: "third"), options: .init(), directory: root, date: date)
        precondition(FileManager.default.fileExists(atPath: a.url.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: a.url.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let bookmark = try a.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        let restored = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        precondition(restored.resolvingSymlinksInPath().path == a.url.resolvingSymlinksInPath().path && !stale)

        for invalid in ["", " \t\n", String(repeating: "x", count: QuickNoteText.maximumTextBytes + 1)] {
            do { _ = try await service.create(.init(text: invalid), options: .init(), directory: root); preconditionFailure("Invalid text was accepted") }
            catch let error as QuickNoteError { precondition(error == .empty || error == .tooLarge) }
        }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("untouched".utf8).write(to: blocked)
        do { _ = try await service.create(.init(text: "private payload"), options: .init(), directory: blocked); preconditionFailure("Write should fail") }
        catch let error as QuickNoteError { precondition(error == .storage && !error.rawValue.contains("private payload")) }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(!remaining.contains { $0.hasPrefix(".nodebay-note-") })
        let failedRoot = root.appendingPathComponent("failed-write")
        let failingWriter = QuickNoteService(write: { handle, bytes in
            try handle.write(contentsOf: bytes.prefix(3))
            throw QuickNoteError.storage
        })
        do { _ = try await failingWriter.create(.init(text: "never promote partial content"), options: .init(), directory: failedRoot); preconditionFailure("Partial write was promoted") }
        catch let error as QuickNoteError { precondition(error == .storage) }
        let failedFiles = try FileManager.default.contentsOfDirectory(atPath: failedRoot.path)
        precondition(failedFiles.isEmpty)

        let urls = "https://youtube.com/watch?v=one\nhttps://youtu.be/two\nhttps://youtu.be/two"
        guard case .downloads(let downloads) = ShelfPasteRoute.decide(.init(text: urls), notesEnabled: true) else { preconditionFailure("URL routing failed") }
        precondition(downloads.count == 2)
        precondition(ShelfPasteRoute.decide(.init(text: "https://music.youtube.com/watch?v=one"), notesEnabled: true) == .downloads([URL(string: "https://music.youtube.com/watch?v=one")!]))
        for prose in ["See https://youtube.com/watch?v=x", "https://youtu.be/x\nSome context", "[video](https://youtu.be/x)", "https://user:password@example.test", "normal text", "ftp://example.test/file"] {
            precondition(ShelfPasteRoute.decide(.init(text: prose), notesEnabled: true) == .note)
            precondition(ShelfPasteRoute.decide(.init(text: prose), notesEnabled: false) == .unhandled)
        }
        precondition(ShelfPasteRoute.decide(.init(text: " "), notesEnabled: true) == .unhandled)
        precondition(ShelfPasteRoute.decide(.init(text: a.url.absoluteString), notesEnabled: true) == .files([a.url]))
        precondition(ShelfPasteRoute.decide(.init(text: urls, fileURLs: [a.url]), notesEnabled: true) == .files([a.url]))

        let unsafeHeadings = ["# ../../secret", "# API key sk-private", "# My confidential sentence", "# foo/bar:*?<>|", "```\n# Notes\n```", "# 🚀秘密"]
        for text in unsafeHeadings {
            let stem = QuickNoteText.filenameStem(text, options: .init(preferHeading: true), date: date)
            precondition(stem.hasPrefix("Quick Note ") && !stem.contains("/"))
        }
        precondition(QuickNoteText.filenameStem("# Notes\nbody", options: .init(preferHeading: true), date: date) == "Notes")
        precondition(QuickNoteText.filenameStem("# Notes\nbody", options: .init(), date: date).hasPrefix("Quick Note "))

        let html = Data("<h1>Notes</h1><p>Hello <strong>world</strong></p><ul><li>First</li><li>Second</li></ul><pre><code>let x = 1;</code></pre>".utf8)
        let rich = try QuickNoteText.prepare(.init(text: "Notes\nHello world\nFirst\nSecond\nlet x = 1;", html: html), rich: true)
        precondition(rich.1 == "HTML" && rich.0.contains("**world**") && rich.0.contains("- First") && rich.0.contains("```\nlet x = 1;"))
        let markdown = "# Already Markdown\n\n```\na < b\n```"
        let unchangedMarkdown = try QuickNoteText.prepare(.init(text: markdown, html: html), rich: true)
        precondition(unchangedMarkdown.0 == markdown)
        for start in [String(Int.min), String(Int.max), "-1", "not-a-number"] {
            let invalidList = Data("<ol start='\(start)'><li>plain fallback</li></ol>".utf8)
            let result = try QuickNoteText.prepare(.init(text: "plain fallback", html: invalidList), rich: true)
            precondition(result == ("plain fallback", "Plain text"))
        }
        for untrusted in ["<img src='https://example.test/track'/>", "<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><p>&e;</p>", "<p>broken", String(repeating: "<div>", count: 40) + "deep" + String(repeating: "</div>", count: 40)] {
            let result = try QuickNoteText.prepare(.init(text: "plain fallback", html: Data(untrusted.utf8)), rich: true)
            precondition(result == ("plain fallback", "Plain text"))
        }
        let rtf = Data("{\\rtf1\\ansi A \\b bold\\b0  word}".utf8)
        let rtfResult = try QuickNoteText.prepare(.init(text: "A bold word", rtf: rtf), rich: true)
        precondition(rtfResult.0.contains("**bold**") && rtfResult.1 == "RTF")
        let fallback = try QuickNoteText.prepare(.init(text: "exact", rtf: Data("invalid".utf8)), rich: true)
        precondition(fallback == ("exact", "Plain text"))
        let oversizedRichFallback = try QuickNoteText.prepare(.init(text: "small plain text", html: Data(repeating: 65, count: QuickNoteText.maximumRichBytes + 1)), rich: true)
        precondition(oversizedRichFallback == ("small plain text", "Plain text"))
        print("Quick Notes behavioral fixtures passed")
    }
}

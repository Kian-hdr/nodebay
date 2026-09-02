import AppKit
import XCTest
@testable import NodebayMarkdown

final class MarkdownRendererTests: XCTestCase {
    func testBlocksAndInlineFormatting() {
        let value = MarkdownRenderer.render("# Heading\n\nHello **bold** and *italic*, `code`.\n\n> Quote\n\n- One\n- [x] Done\n- [ ] Later\n\n```swift\nlet x = 1\n```\n")
        XCTAssertTrue(value.string.contains("Heading\nHello bold and italic, code."))
        XCTAssertTrue(value.string.contains("│ Quote"))
        XCTAssertTrue(value.string.contains("•\tOne"))
        XCTAssertTrue(value.string.contains("☑\tDone"))
        XCTAssertTrue(value.string.contains("☐\tLater"))
        XCTAssertTrue(value.string.contains("let x = 1"))
        let range = (value.string as NSString).range(of: "bold")
        let font = value.attribute(.font, at: range.location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testTablesAreNativeSelectableText() {
        let value = MarkdownRenderer.render("| A | B |\n|---|---|\n| One | Two |")
        XCTAssertEqual(value.string, "A\nB\nOne\nTwo")
        let p = value.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(p.textBlocks.count, 1)
        XCTAssertTrue(p.textBlocks[0] is NSTextTableBlock)
    }

    func testNoExternalResourcesOrUnsafeLinks() {
        let value = MarkdownRenderer.render("![alt](https://invalid.example/image) [bad](javascript:alert) [safe](https://example.com) <script>alert(1)</script>")
        XCTAssertTrue(value.string.contains("alt"))
        var links: [URL] = []
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attrs, _, _ in
            XCTAssertNil(attrs[.attachment])
            if let link = attrs[.link] as? URL { links.append(link) }
        }
        XCTAssertEqual(links.map(\.scheme), ["https"])
    }

    func testUnicodeAndMalformedMarkdown() {
        let value = MarkdownRenderer.render("# café 🌿 日本語\n\n**unfinished\n\n```\ncode")
        XCTAssertTrue(value.string.contains("café 🌿 日本語"))
        XCTAssertTrue(value.string.contains("code"))
        XCTAssertEqual(MarkdownRenderer.render("").length, 0)
    }

    func testLargeInputFallsBackWithBoundedOutput() {
        let text = String(repeating: "🌿hello\n", count: 80_000)
        let value = MarkdownRenderer.render(text)
        XCTAssertTrue(value.string.contains("bounded plain-text preview"))
        XCTAssertLessThan(value.string.count, MarkdownRenderer.maximumDisplayedCharacters + 100)
    }

    func testFileReadIsBoundedAndDoesNotModifySource() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Unicode 🌿.md")
        let bytes = Data("# A\r\ntext\rnext".utf8)
        try bytes.write(to: url)
        XCTAssertEqual(try MarkdownRenderer.read(url), "# A\ntext\nnext")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try Data(repeating: 1, count: MarkdownRenderer.maximumFileBytes + 1).write(to: url)
        XCTAssertThrowsError(try MarkdownRenderer.read(url))
        XCTAssertThrowsError(try MarkdownRenderer.read(folder))
        XCTAssertThrowsError(try MarkdownRenderer.read(URL(string: "https://example.com")!))
        try Data([0, 1, 255]).write(to: url)
        XCTAssertThrowsError(try MarkdownRenderer.read(url))
    }

    func testUTF16AndMarkdownExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".markdown")
        defer { try? FileManager.default.removeItem(at: url) }
        try "# 日本語\n\nUnicode 🌿".data(using: .utf16)!.write(to: url)
        XCTAssertEqual(try MarkdownRenderer.read(url), "# 日本語\n\nUnicode 🌿")
    }

    func testOrderedNestedListsAndCodePreserveText() {
        let value = MarkdownRenderer.render("1. First\n2. Second\n   - Nested\n\n```\nline 1\n  line 2\n```\n")
        XCTAssertTrue(value.string.contains("1.\tFirst"))
        XCTAssertTrue(value.string.contains("2.\tSecond"))
        XCTAssertTrue(value.string.contains("•\tNested"))
        XCTAssertTrue(value.string.contains("line 1\n  line 2\n"))
    }
}

import AppKit
import XCTest
@testable import NodebayMarkdown

final class MarkdownRendererTests: XCTestCase {
    func testAdjacentIdenticalMermaidFencesKeepIndependentIdentity() {
        let fence = "```mermaid\nflowchart LR\nA --> B\n```\n"
        let value = MarkdownRenderer.render(fence + "\n" + fence)
        var identities: [Int] = []
        var sources: [String] = []
        value.enumerateAttribute(MarkdownRenderer.mermaidBlockIdentityAttribute,
                                 in: NSRange(location: 0, length: value.length)) { identity, range, _ in
            if let identity = identity as? Int {
                identities.append(identity)
                sources.append(value.attribute(MarkdownRenderer.mermaidSourceAttribute,
                                               at: range.location, effectiveRange: nil) as! String)
            }
        }
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(Set(identities).count, 2)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.first, sources.last)
    }

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

    func testTableHasMeasuredOuterGapBeforeCodeAndParagraph() {
        let table = "| Header A | Header B |\n|---|---|\n| Final A | Final B |\n\n"
        for width in [CGFloat(320), CGFloat(712)] {
            for suffix in ["```\nafterTable\n```", "afterTable paragraph", "## afterTable heading"] {
                let layout = MeasuredLayout(MarkdownRenderer.render(table + suffix), width: width)
                let lastCell = layout.range("Final B").location
                let style = layout.text.attribute(.paragraphStyle, at: lastCell, effectiveRange: nil) as! NSParagraphStyle
                let cell = style.textBlocks.first as! NSTextTableBlock
                let glyph = layout.manager.glyphIndexForCharacter(at: lastCell)
                // Cell bounds include padding and borders, unlike glyph ink bounds.
                let borderBounds = layout.manager.boundsRect(for: cell, at: glyph, effectiveRange: nil)
                XCTAssertGreaterThan(borderBounds.height, 0)
                let gap = layout.line("afterTable").minY - borderBounds.maxY
                XCTAssertGreaterThanOrEqual(gap, suffix.hasPrefix("##") ? 18 : 10,
                    "Table border touches following content at width \(width): gap \(gap)")
                XCTAssertLessThanOrEqual(gap, 34, "Table boundary gained an accidental blank paragraph: gap \(gap)")
                XCTAssertFalse(layout.text.string.contains("Final B\n\n"), "Spacing must not change copied text")
            }
        }
    }

    func testTableRightEdgeFitsAndPaintsAfterWrappingAtBothPreviewWidths() {
        _ = NSApplication.shared
        let fixtures: [(String, [String])] = [
            ("| Feature | Behavior |\n|---|---|\n| Text | Select and copy |\n| Resources | Local only |",
             ["Feature", "Behavior", "Text", "Select and copy", "Resources", "Local only"]),
            ("| First column | Middle column | Last column |\n|---|---|---|\n| A longer sentence with words that must wrap | Middle content remains selectable while wrapping | Final content remains visible right to the end |",
             ["First column", "Middle column", "Last column", "A longer sentence with words that must wrap", "Middle content remains selectable while wrapping", "Final content remains visible right to the end"])
        ]
        for (source, cells) in fixtures {
            let rendered = MarkdownRenderer.render(source)
            for width in [CGFloat(320), CGFloat(712)] {
                let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 720))
                view.appearance = NSAppearance(named: .aqua)
                view.drawsBackground = true
                view.backgroundColor = .white
                view.textContainerInset = NSSize(width: 24, height: 20)
                view.textContainer!.lineFragmentPadding = 0
                view.textContainer!.widthTracksTextView = true
                view.isHorizontallyResizable = false
                view.isVerticallyResizable = true
                view.autoresizingMask = [.width]
                let scroll = NSScrollView(frame: view.frame)
                scroll.hasVerticalScroller = true
                scroll.scrollerStyle = .overlay
                scroll.documentView = view
                view.textStorage!.setAttributedString(rendered)
                let manager = view.layoutManager!
                let container = view.textContainer!
                manager.ensureLayout(for: container)
                var tableBounds = NSRect.null
                rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { style, range, _ in
                    if let cell = (style as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock {
                        let bounds = manager.boundsRect(for: cell,
                            at: manager.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
                        tableBounds = tableBounds.union(bounds)
                    }
                }
                XCTAssertFalse(tableBounds.isNull)
                let origin = view.textContainerOrigin
                let physicalRight = tableBounds.maxX + origin.x
                XCTAssertLessThanOrEqual(physicalRight, scroll.contentView.bounds.width - 20,
                                         "The complete table must retain reading-area padding")
                for cell in cells {
                    let range = (rendered.string as NSString).range(of: cell)
                    XCTAssertNotEqual(range.location, NSNotFound, "Every cell's full text must remain selectable")
                    if range.location != NSNotFound {
                        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                        let ink = manager.boundingRect(forGlyphRange: glyphs, in: container)
                        XCTAssertLessThanOrEqual(ink.maxX + origin.x, scroll.contentView.bounds.width - 20,
                                                 "Wrapped cell text must stay inside the reading area")
                    }
                }
                // Layout bounds can fit while AppKit omits the collapsed table's
                // final vertical stroke. Verify the actual painted pixels too.
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
                let top = Int((tableBounds.minY + origin.y + 3) * scale)
                let bottom = min(bitmap.pixelsHigh, Int((tableBounds.maxY + origin.y - 3) * scale))
                let left = max(0, Int((physicalRight - 3) * scale))
                let right = min(bitmap.pixelsWide - 1, Int((physicalRight + 1) * scale))
                XCTAssertGreaterThan(bottom, top)
                var strongestStroke = 0
                for x in left...right {
                    var darkPixels = 0
                    for y in top..<bottom {
                        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           color.redComponent < 0.5, color.greenComponent < 0.5, color.blueComponent < 0.5 {
                            darkPixels += 1
                        }
                    }
                    strongestStroke = max(strongestStroke, darkPixels)
                }
                let coverage = Double(strongestStroke) / Double(max(1, bottom - top))
                XCTAssertGreaterThan(coverage, 0.8,
                    "Right border must actually paint, not only fit in layout bounds (width \(width), coverage \(coverage))")
            }
        }
    }

    func testCodeLinesStayCompactAndBlankLinesArePreserved() {
        let layout = MeasuredLayout(MarkdownRenderer.render("```\nfirstCode\nsecondCode\n\nfourthCode\n```\n\nafterCode"))
        XCTAssertTrue(layout.text.string.contains("firstCode\nsecondCode\n\nfourthCode\n"))
        let first = layout.line("firstCode")
        let second = layout.line("secondCode")
        let fourth = layout.line("fourthCode")
        let font = layout.text.attribute(.font, at: layout.range("firstCode").location, effectiveRange: nil) as! NSFont
        let naturalHeight = layout.manager.defaultLineHeight(for: font)
        let step = second.minY - first.minY
        XCTAssertGreaterThanOrEqual(step, naturalHeight - 1)
        XCTAssertLessThanOrEqual(step, naturalHeight + 3, "Paragraph gaps must not be applied to each code line")
        XCTAssertEqual(fourth.minY - second.minY, 2 * step, accuracy: 1, "An intentional blank code line must occupy one line")
        XCTAssertGreaterThanOrEqual(layout.line("afterCode").minY - fourth.maxY, 10)
    }

    func testHeadingsHaveNoLeadingDocumentGapAndSeparateSections() {
        let start = MeasuredLayout(MarkdownRenderer.render("# First heading\n\nOpening paragraph"))
        XCTAssertEqual(start.line("First heading").minY, 0, accuracy: 1)
        XCTAssertGreaterThanOrEqual(start.line("Opening paragraph").minY - start.line("First heading").maxY, 10)
        let later = MeasuredLayout(MarkdownRenderer.render("Previous paragraph\n\n## Later heading\n\nNext paragraph"))
        let gap = later.line("Later heading").minY - later.line("Previous paragraph").maxY
        XCTAssertGreaterThanOrEqual(gap, 18)
        XCTAssertLessThanOrEqual(gap, 34)
        XCTAssertGreaterThanOrEqual(later.line("Next paragraph").minY - later.line("Later heading").maxY, 10)
    }

    func testListHasCompactSiblingsAndLargerOuterGap() {
        let layout = MeasuredLayout(MarkdownRenderer.render("Before list\n\n- First item\n- Second item\n\nAfter list"))
        let siblingGap = layout.line("Second item").minY - layout.line("First item").maxY
        let outerGap = layout.line("After list").minY - layout.line("Second item").maxY
        XCTAssertGreaterThanOrEqual(siblingGap, 2)
        XCTAssertLessThanOrEqual(siblingGap, 6)
        XCTAssertGreaterThanOrEqual(outerGap, 10)
        XCTAssertGreaterThan(outerGap, siblingGap)
        XCTAssertGreaterThanOrEqual(layout.line("First item").minY - layout.line("Before list").maxY, 10)
    }

    func testListContinuationDoesNotRepeatMarkerAndInlineRunsKeepSpacing() {
        let source = "- First **bold** item\n\n  Continuation paragraph\n\n- Second item\n\nAfter list"
        let value = MarkdownRenderer.render(source)
        XCTAssertEqual(value.string.components(separatedBy: "•\t").count - 1, 2)
        XCTAssertFalse(value.string.contains("•\tContinuation"))
        let first = (value.string as NSString).range(of: "First").location
        let continuation = (value.string as NSString).range(of: "Continuation").location
        let firstStyle = value.attribute(.paragraphStyle, at: first, effectiveRange: nil) as! NSParagraphStyle
        let continuationStyle = value.attribute(.paragraphStyle, at: continuation, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(continuationStyle.firstLineHeadIndent, firstStyle.headIndent)
        let plain = MeasuredLayout(MarkdownRenderer.render("One plain paragraph\n\nNext block"))
        let inline = MeasuredLayout(MarkdownRenderer.render("One **plain** paragraph\n\nNext block"))
        XCTAssertEqual(plain.line("Next block").minY, inline.line("Next block").minY, accuracy: 1)
    }

    func testMermaidFencesCarryIndependentCompleteSourcesWithoutMarkingOrdinaryCode() {
        let first = "flowchart TD\n  A --> B\n"
        let second = "sequenceDiagram\n  Alice->>Bob: Hello\n"
        let value = MarkdownRenderer.render("Before diagrams\n\n```mermaid\n\(first)```\n\nBetween diagrams\n\n```swift\nlet ordinary = 1\n```\n\n```mermaid\n\(second)```\n\nAfter diagrams")
        var sources: [String] = []
        value.enumerateAttribute(MarkdownRenderer.mermaidSourceAttribute,
                                 in: NSRange(location: 0, length: value.length)) { source, range, _ in
            guard let source = source as? String else { return }
            sources.append(source)
            XCTAssertEqual(value.attributedSubstring(from: range).string, source,
                           "Diagram marker must cover exactly its complete source")
        }
        XCTAssertEqual(sources, [first, second])
        for text in ["Before diagrams", "Between diagrams", "let ordinary = 1", "After diagrams"] {
            let range = (value.string as NSString).range(of: text)
            XCTAssertNotEqual(range.location, NSNotFound)
            if range.location != NSNotFound {
                XCTAssertNil(value.attribute(MarkdownRenderer.mermaidSourceAttribute, at: range.location, effectiveRange: nil))
            }
        }
    }
}

private final class MeasuredLayout {
    let text: NSAttributedString
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer

    init(_ text: NSAttributedString, width: CGFloat = 712) {
        self.text = text
        storage = NSTextStorage(attributedString: text)
        container = NSTextContainer(size: NSSize(width: width, height: 100_000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
    }

    func range(_ needle: String) -> NSRange {
        let found = (text.string as NSString).range(of: needle)
        precondition(found.location != NSNotFound, "Missing rendered fixture text: \(needle)")
        return found
    }

    func line(_ needle: String) -> NSRect {
        manager.lineFragmentUsedRect(forGlyphAt: manager.glyphIndexForCharacter(at: range(needle).location), effectiveRange: nil)
    }
}

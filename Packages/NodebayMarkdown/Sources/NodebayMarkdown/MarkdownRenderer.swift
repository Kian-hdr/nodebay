// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation

/// Local-only, reusable rendering. No HTML, WebKit, attachments, scripts or resource loading.
public enum MarkdownRenderer {
    /// Fenced Mermaid source remains selectable until the preview supplies a local diagram.
    public static let mermaidSourceAttribute = NSAttributedString.Key("NodebayMermaidSource")
    public static let mermaidBlockIdentityAttribute = NSAttributedString.Key("NodebayMermaidBlockIdentity")

    public static let maximumFileBytes = 2 * 1024 * 1024
    public static let maximumRenderedBytes = 256 * 1024
    public static let maximumDisplayedCharacters = 256 * 1024

    public enum PreviewError: Error { case unreadable, unsupportedEncoding, tooLarge }

    public static func read(_ url: URL) throws -> String {
        guard url.isFileURL else { throw PreviewError.unreadable }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw PreviewError.unreadable }
        guard (values.fileSize ?? Int.max) <= maximumFileBytes else { throw PreviewError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw PreviewError.tooLarge }
        var text: String?
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text, !text.contains("\0") else { throw PreviewError.unsupportedEncoding }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public static func render(_ source: String) -> NSAttributedString {
        guard source.utf8.count <= maximumRenderedBytes else {
            return plainText(source, notice: "Large document: showing a bounded plain-text preview.")
        }
        do {
            let parsed = try AttributedString(markdown: source, options: .init(
                allowsExtendedAttributes: false, interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible))
            return renderParsed(parsed)
        } catch {
            return plainText(source, notice: "Markdown formatting unavailable. Showing plain text.")
        }
    }

    public static func plainText(_ source: String, notice: String? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: String(source.prefix(maximumDisplayedCharacters)),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.textColor])
        if let notice {
            result.append(NSAttributedString(string: "\n\n[\(notice)]", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return result
    }

    // Temporary layout metadata is removed before returning selectable document text.
    private static let blockKindKey = NSAttributedString.Key("NodebayBlockKind")
    private static let blockGroupKey = NSAttributedString.Key("NodebayBlockGroup")
    private static let blockLeafKey = NSAttributedString.Key("NodebayBlockLeaf")

    private static func renderParsed(_ parsed: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        var tables: [Int: NSTextTable] = [:]
        var blockCount = 0
        var prefixedListItems = Set<Int>()
        var mermaidBlocks: [Int: (range: NSRange, source: String)] = [:]
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let blockID = components.first?.identity ?? 0
            let newBlock = previousBlock != blockID
            if newBlock {
                blockCount += 1
                if blockCount > 5000 {
                    result.append(plainText("\n[Preview limited to 5,000 blocks.]"))
                    break
                }
                if result.length > 0, !result.string.hasSuffix("\n") {
                    // The terminator belongs to the preceding paragraph, including its table cell.
                    result.append(NSAttributedString(string: "\n",
                        attributes: result.attributes(at: result.length - 1, effectiveRange: nil)))
                }
            }
            previousBlock = blockID
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 12
            paragraph.lineSpacing = 3
            paragraph.tabStops = []
            var font = NSFont.systemFont(ofSize: 13)
            var code = false
            var codeID: Int?
            var mermaid = false
            var heading = false
            var outerListID: Int?
            var listItemID: Int?
            var tableID: Int?
            var prefix = ""
            var listOrdinal: Int?
            var ordered = false
            var listDepth = 0
            var table: NSTextTable?
            var tableRow = 0
            var tableColumn = 0
            var tableHeader = false
            var quoteDepth = 0
            for component in components.reversed() {
                switch component.kind {
                case .header(let level):
                    heading = true
                    font = NSFont.systemFont(ofSize: [22, 19, 17, 15, 14, 13][max(0, min(5, level - 1))], weight: .semibold)
                    paragraph.paragraphSpacingBefore = 20
                case .codeBlock(let language):
                    code = true
                    mermaid = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mermaid"
                    codeID = component.identity
                    font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    paragraph.lineSpacing = 2
                    paragraph.paragraphSpacing = 0
                case .orderedList:
                    ordered = true; listDepth += 1
                    if outerListID == nil { outerListID = component.identity }
                case .unorderedList:
                    ordered = false; listDepth += 1
                    if outerListID == nil { outerListID = component.identity }
                case .listItem(let ordinal):
                    listOrdinal = ordinal
                    listItemID = component.identity
                case .blockQuote: quoteDepth += 1
                case .table(let columns):
                    tableID = component.identity
                    let existing = tables[component.identity] ?? NSTextTable()
                    existing.numberOfColumns = max(1, columns.count)
                    existing.collapsesBorders = true
                    // AppKit can omit the final cell's right stroke when a collapsed
                    // table has only cell borders. An explicit table border restores it.
                    existing.setWidth(1, type: .absoluteValueType, for: .border)
                    existing.setBorderColor(.labelColor)
                    existing.setValue(100, type: .percentageValueType, for: .width)
                    tables[component.identity] = existing
                    table = existing
                case .tableHeaderRow: tableHeader = true
                case .tableRow(let index): tableRow = index
                case .tableCell(let index): tableColumn = index
                case .thematicBreak: prefix = "────────────────"
                default: break
                }
            }
            var text = String(parsed[run.range].characters)
            if let ordinal = listOrdinal, let listItemID {
                let startsItem = newBlock && !prefixedListItems.contains(listItemID)
                if startsItem { prefixedListItems.insert(listItemID) }
                prefix = startsItem ? (ordered ? "\(ordinal).\t" : "•\t") : ""
                if startsItem, text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                    prefix = text.hasPrefix("[ ]") ? "☐\t" : "☑\t"
                    text.removeFirst(4)
                }
                paragraph.firstLineHeadIndent = CGFloat(max(0, listDepth - 1)) * 24
                paragraph.headIndent = CGFloat(listDepth) * 24
                if !startsItem { paragraph.firstLineHeadIndent = paragraph.headIndent }
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                paragraph.paragraphSpacing = 4
            }
            if quoteDepth > 0 {
                paragraph.headIndent += CGFloat(quoteDepth) * 16
                paragraph.firstLineHeadIndent += CGFloat(quoteDepth) * 16
                prefix = "│ " + prefix
            }
            if let table {
                let cell = NSTextTableBlock(table: table, startingRow: tableRow, rowSpan: 1,
                    startingColumn: tableColumn, columnSpan: 1)
                cell.setWidth(6, type: .absoluteValueType, for: .padding)
                // A table grid must stay legible on both opaque and glass reading surfaces.
                cell.setWidth(1, type: .absoluteValueType, for: .border)
                cell.setBorderColor(.labelColor)
                paragraph.textBlocks = [cell]
                paragraph.paragraphSpacing = 0
                if tableHeader { font = .systemFont(ofSize: 13, weight: .semibold) }
            }
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.code) { font = .monospacedSystemFont(ofSize: 12, weight: .regular) }
            var traits = font.fontDescriptor.symbolicTraits
            if inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if inline.contains(.emphasized) { traits.insert(.italic) }
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph,
                blockKindKey: table != nil ? "table" : (code ? "code" : (heading ? "heading" : (listItemID != nil ? "list" : "paragraph"))),
                blockGroupKey: tableID ?? codeID ?? outerListID ?? blockID,
                blockLeafKey: blockID]
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let url = run.link, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? ""),
               url.user == nil, url.password == nil {
                attributes[.link] = url
            }
            // Images remain their selectable alt text; never resolve an image URL.
            let fragmentStart = result.length
            if newBlock, !prefix.isEmpty { result.append(NSAttributedString(string: prefix, attributes: attributes)) }
            let fragment = NSMutableAttributedString(string: text, attributes: attributes)
            if code { emphasizeCodeKeywords(fragment) }
            result.append(fragment)
            if mermaid, let codeID {
                let range = NSRange(location: fragmentStart, length: result.length - fragmentStart)
                if let previous = mermaidBlocks[codeID] {
                    mermaidBlocks[codeID] = (NSUnionRange(previous.range, range), previous.source + text)
                } else {
                    mermaidBlocks[codeID] = (range, text)
                }
            }
        }
        if result.length == 0 { return plainText("") }
        applyBlockSpacing(to: result)
        for (identity, block) in mermaidBlocks {
            result.addAttribute(mermaidSourceAttribute, value: block.source, range: block.range)
            result.addAttribute(mermaidBlockIdentityAttribute, value: identity, range: block.range)
        }
        return result
    }

    /// Space semantic blocks, not inline formatting runs or each line inside a code block.
    private static func applyBlockSpacing(to text: NSMutableAttributedString) {
        let string = text.string as NSString
        var paragraphs: [(range: NSRange, kind: String, group: Int, leaf: Int)] = []
        var location = 0
        while location < text.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let attributes = text.attributes(at: location, effectiveRange: nil)
            paragraphs.append((range, attributes[blockKindKey] as? String ?? "paragraph",
                               attributes[blockGroupKey] as? Int ?? -1,
                               attributes[blockLeafKey] as? Int ?? -1))
            location = NSMaxRange(range)
        }
        for (index, current) in paragraphs.enumerated() {
            guard let original = text.attribute(.paragraphStyle, at: current.range.location,
                                                effectiveRange: nil) as? NSParagraphStyle,
                  let style = original.mutableCopy() as? NSMutableParagraphStyle else { continue }
            let next = index + 1 < paragraphs.count ? paragraphs[index + 1] : nil
            let previous = index > 0 ? paragraphs[index - 1] : nil
            style.paragraphSpacingBefore = 0
            if current.kind == "heading", index > 0 {
                style.paragraphSpacingBefore = 20
            } else if previous?.kind == "table", current.kind != "table" {
                // TextKit does not reserve vertical table margins. Put the gap on
                // the following paragraph, outside the cell's border and padding.
                style.paragraphSpacingBefore = 12
            }
            if current.kind == "table" {
                style.paragraphSpacing = 0
            } else if next?.kind == "heading" {
                // Headings own their leading gap; avoid stacking two margins.
                style.paragraphSpacing = 0
            } else if let next, next.group == current.group {
                style.paragraphSpacing = current.leaf == next.leaf || current.kind == "code" ? 0 : 4
            } else {
                style.paragraphSpacing = 12
            }
            text.addAttribute(.paragraphStyle, value: style, range: current.range)
        }
        let whole = NSRange(location: 0, length: text.length)
        for key in [blockKindKey, blockGroupKey, blockLeafKey] {
            text.removeAttribute(key, range: whole)
        }
    }

    private static func emphasizeCodeKeywords(_ text: NSMutableAttributedString) {
        // Restrained language-neutral emphasis, not a claimed full syntax parser.
        guard text.length < 32_768,
              let expression = try? NSRegularExpression(pattern: "\\b(let|var|func|class|struct|enum|import|return|if|else|for|while|def|const|true|false|null|nil)\\b") else { return }
        for match in expression.matches(in: text.string, range: NSRange(location: 0, length: text.length)) {
            text.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), range: match.range)
        }
    }
}

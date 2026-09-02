// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation

/// Local-only, reusable rendering. No HTML, WebKit, attachments, scripts or resource loading.
public enum MarkdownRenderer {
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

    private static func renderParsed(_ parsed: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        var tables: [Int: NSTextTable] = [:]
        var blockCount = 0
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
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            }
            previousBlock = blockID
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 8
            paragraph.lineSpacing = 2
            paragraph.tabStops = []
            var font = NSFont.systemFont(ofSize: 13)
            var code = false
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
                    font = NSFont.systemFont(ofSize: [22, 19, 17, 15, 14, 13][max(0, min(5, level - 1))], weight: .semibold)
                    paragraph.paragraphSpacingBefore = 6
                case .codeBlock:
                    code = true
                    font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    paragraph.lineSpacing = 1
                case .orderedList: ordered = true; listDepth += 1
                case .unorderedList: ordered = false; listDepth += 1
                case .listItem(let ordinal): listOrdinal = ordinal
                case .blockQuote: quoteDepth += 1
                case .table(let columns):
                    let existing = tables[component.identity] ?? NSTextTable()
                    existing.numberOfColumns = max(1, columns.count)
                    existing.collapsesBorders = true
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
            if let ordinal = listOrdinal {
                prefix = ordered ? "\(ordinal).\t" : "•\t"
                if newBlock, text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                    prefix = text.hasPrefix("[ ]") ? "☐\t" : "☑\t"
                    text.removeFirst(4)
                }
                paragraph.firstLineHeadIndent = CGFloat(max(0, listDepth - 1)) * 20
                paragraph.headIndent = CGFloat(listDepth) * 20
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
                cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                cell.setBorderColor(.separatorColor)
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
                .font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let url = run.link, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? ""),
               url.user == nil, url.password == nil {
                attributes[.link] = url
            }
            // Images remain their selectable alt text; never resolve an image URL.
            if newBlock, !prefix.isEmpty { result.append(NSAttributedString(string: prefix, attributes: attributes)) }
            let fragment = NSMutableAttributedString(string: text, attributes: attributes)
            if code { emphasizeCodeKeywords(fragment) }
            result.append(fragment)
        }
        if result.length == 0 { return plainText("") }
        return result
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

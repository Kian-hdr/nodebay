// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import NodebayMarkdown

/// Native text remains available immediately; diagrams replace only their own code blocks.
@MainActor
final class MarkdownDiagramPresenter {
    private let renderer = MermaidDiagramRenderer()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        renderer.cancel()
    }

    func display(_ source: NSAttributedString, in textView: NSTextView) {
        cancel()
        textView.textStorage?.setAttributedString(source)
        let request = generation
        var diagrams: [(range: NSRange, source: String)] = []
        source.enumerateAttribute(MarkdownRenderer.mermaidBlockIdentityAttribute,
                                  in: NSRange(location: 0, length: source.length)) { identity, range, _ in
            if identity != nil,
               let code = source.attribute(MarkdownRenderer.mermaidSourceAttribute,
                                           at: range.location, effectiveRange: nil) as? String {
                diagrams.append((range, code))
            }
        }
        guard !diagrams.isEmpty else { return }
        let dark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        task = Task { [weak self, weak textView] in
            guard let self, let textView else { return }
            var offset = 0
            for (index, diagram) in diagrams.enumerated() {
                guard !Task.isCancelled, generation == request else { return }
                let replacement: NSAttributedString
                do {
                    guard index < 12 else { throw MermaidDiagramRenderer.RenderError.tooComplex }
                    let image = try await renderer.render(diagram.source, dark: dark)
                    guard !Task.isCancelled, generation == request else { return }
                    replacement = Self.attachment(image, source: source, range: diagram.range)
                } catch {
                    guard !Task.isCancelled, generation == request else { return }
                    replacement = Self.fallback(source: source, range: diagram.range,
                                                limit: index >= 12)
                }
                let range = NSRange(location: diagram.range.location + offset, length: diagram.range.length)
                textView.textStorage?.replaceCharacters(in: range, with: replacement)
                offset += replacement.length - diagram.range.length
            }
        }
    }

    private static func attachment(_ image: NSImage, source: NSAttributedString, range: NSRange) -> NSAttributedString {
        let attachment = MermaidImageAttachment()
        attachment.image = image
        attachment.allowsTextAttachmentView = false
        let result = NSMutableAttributedString(attachment: attachment)
        var attributes = source.attributes(at: range.location, effectiveRange: nil)
        attributes.removeValue(forKey: MarkdownRenderer.mermaidSourceAttribute)
        attributes.removeValue(forKey: MarkdownRenderer.mermaidBlockIdentityAttribute)
        let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 12
        paragraph.lineSpacing = 0
        attributes[.paragraphStyle] = paragraph
        attributes[.toolTip] = "Mermaid diagram"
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        // Preserve the existing block terminator, without introducing a blank text paragraph.
        if source.attributedSubstring(from: range).string.hasSuffix("\n") {
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        return result
    }

    private static func fallback(source: NSAttributedString, range: NSRange, limit: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        let message = limit ? "Additional Mermaid diagram shown as source (preview limit)."
                            : "Mermaid diagram could not be rendered. Source shown below."
        let result = NSMutableAttributedString(string: message + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph])
        result.append(source.attributedSubstring(from: range))
        for key in [MarkdownRenderer.mermaidSourceAttribute, MarkdownRenderer.mermaidBlockIdentityAttribute] {
            result.removeAttribute(key, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}

/// Let TextKit recompute the image size as the Quick Look window is resized.
final class MermaidImageAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let available = max(1, lineFrag.width - max(0, position.x - lineFrag.minX))
        let scale = min(1, available / image.size.width)
        return NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
    }
}

final class MarkdownPreviewTextView: NSTextView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}

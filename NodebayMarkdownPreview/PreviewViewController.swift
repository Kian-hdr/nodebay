// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Quartz
import NodebayMarkdown

/// The host owns all window chrome and materials. This controller supplies only document content.
final class PreviewViewController: NSViewController, QLPreviewingController, NSTextViewDelegate {
    private let textView = NSTextView()
    private var generation = UUID()
    private let worker = DispatchQueue(label: "Nodebay.MarkdownPreview", qos: .userInitiated)

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 720))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = false
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 7, height: 5)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = scroll.contentView.bounds
        textView.setAccessibilityLabel("Markdown document")
        scroll.documentView = textView
        view = scroll
        preferredContentSize = NSSize(width: 760, height: 720)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        loadViewIfNeeded()
        let request = UUID()
        generation = request
        worker.async { [weak self] in
            let content: NSAttributedString
            do { content = MarkdownRenderer.render(try MarkdownRenderer.read(url)) }
            catch MarkdownRenderer.PreviewError.tooLarge {
                content = MarkdownRenderer.plainText("This document exceeds the 2 MiB preview limit. Open it in an editor to read the complete file.")
            } catch {
                content = MarkdownRenderer.plainText("This document could not be previewed. It may be unavailable or use an unsupported text encoding.")
            }
            DispatchQueue.main.async { [weak self] in
                if let self, self.generation == request {
                    self.textView.textStorage?.setAttributedString(content)
                    self.textView.scrollToBeginningOfDocument(nil)
                }
                handler(nil)
            }
        }
    }

    // Keep preview links selectable/copyable, without opening resources from the extension.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { true }
}

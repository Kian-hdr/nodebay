import AppKit
import SwiftUI

/// One semantic input surface inside the existing notch. AppKit owns editing,
/// selection, undo, marked text and the focus ring; SwiftUI owns composition.
struct QuickChatComposer: View {
    @Binding var text: String
    @Binding var editing: Bool
    let canSend: Bool
    let generating: Bool
    let send: () -> Void
    let stop: () -> Void
    var interactionChanged: (Bool) -> Void = { _ in }
    var userActivity: () -> Void = {}
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            QuickChatEditor(text: $text, editing: $editing, send: send,
                            interactionChanged: interactionChanged, userActivity: userActivity)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text("Message Quick Chat…")
                            .font(.system(size: QuickChatEditorMetrics.fontSize))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 7)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            Button(action: generating ? stop : send) {
                Image(systemName: generating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!generating && !canSend)
            .help(generating ? "Stop reply" : "Send (Return); Shift-Return adds a line")
            .accessibilityLabel(generating ? "Stop reply" : "Send message")
        }
        .padding(.leading, 6).padding(.trailing, 3).padding(.vertical, 2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
    }
}

enum QuickChatEditorMetrics {
    static let fontSize: CGFloat = 12
    static let minimumHeight: CGFloat = 24
    static let maximumHeight: CGFloat = 54

    static func height(for text: String, width: CGFloat) -> CGFloat {
        layout(for: text, width: width).height
    }

    static func layout(for text: String, width: CGFloat) -> (height: CGFloat, verticalInset: CGFloat) {
        // Empty text storage has no font run and may use AppKit's default
        // extra-line font. Measure a space so empty and typed baselines match.
        let storage = NSTextStorage(string: text.isEmpty ? " " : text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(20, width - 4), height: .greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        // The extra fragment already has a layout position. Adding its height
        // double-counted the empty editor's line and made it taller than a draft.
        let content = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        let height = min(maximumHeight, max(minimumHeight, ceil(content + 4)))
        // Center a short line in the minimum-height viewport. Wrapped/capped
        // text keeps its ordinary two-point inset and native scrolling.
        return (height, max(2, (height - content) / 2))
    }

    static func shouldSend(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, markedText: Bool) -> Bool {
        let editingModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        return [36, 76].contains(keyCode) && modifiers.intersection(editingModifiers).isEmpty && !markedText
    }
}

struct QuickChatEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var editing: Bool
    let send: () -> Void
    var interactionChanged: (Bool) -> Void = { _ in }
    var userActivity: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let view = QuickChatTextView(frame: NSRect(x: 0, y: 0, width: 100, height: QuickChatEditorMetrics.minimumHeight))
        view.delegate = context.coordinator
        view.isRichText = false; view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: QuickChatEditorMetrics.fontSize)
        view.textColor = .labelColor; view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 2, height: 2)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.focusRingType = .exterior
        view.setAccessibilityLabel("Quick Chat message")
        view.setAccessibilityHelp("Return sends. Shift-Return inserts a new line.")
        view.send = { context.coordinator.parent.send() }
        view.focusChanged = { context.coordinator.parent.editing = $0 }
        view.interactionChanged = { context.coordinator.parent.interactionChanged($0) }
        view.onUserActivity = { context.coordinator.parent.userActivity() }
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? QuickChatTextView, !view.hasMarkedText() else { return }
        if view.string != text {
            view.string = text
            view.undoManager?.removeAllActions()
        }
        view.updateVerticalAlignment(width: scroll.contentSize.width)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        (nsView.documentView as? QuickChatTextView)?.updateVerticalAlignment(width: width)
        return CGSize(width: width, height: QuickChatEditorMetrics.height(for: text, width: width))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickChatEditor
        init(_ parent: QuickChatEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.userActivity()
        }
    }
}

@MainActor protocol QuickChatFocusWindow: AnyObject {
    func makeQuickChatFirstResponder(_ responder: NSResponder)
}

class QuickChatFocusableTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?
    var interactionChanged: ((Bool) -> Void)?
    var onUserActivity: (() -> Void)?
    private var trackingSelection = false

    private func updateInteraction() { interactionChanged?(trackingSelection || hasMarkedText()) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onUserActivity?()
        trackingSelection = true; updateInteraction()
        defer { trackingSelection = false; updateInteraction() }
        // The utility panel deliberately refuses keyboard focus on hover.
        // Opt in through its existing explicit-click gate, just like shelf files.
        (window as? any QuickChatFocusWindow)?.makeQuickChatFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true); noteFocusRingMaskChanged() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false); interactionChanged?(false) }
        return accepted
    }

    override func scrollWheel(with event: NSEvent) { onUserActivity?(); super.scrollWheel(with: event) }
    override func keyDown(with event: NSEvent) { onUserActivity?(); super.keyDown(with: event) }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onUserActivity?(); updateInteraction()
    }
    override func unmarkText() { super.unmarkText(); updateInteraction() }
}

final class QuickChatTextView: QuickChatFocusableTextView {
    var send: (() -> Void)?

    func updateVerticalAlignment(width: CGFloat) {
        guard width > 0 else { return }
        let inset = QuickChatEditorMetrics.layout(for: string, width: width).verticalInset
        if textContainerInset.height != inset { textContainerInset = NSSize(width: 2, height: inset) }
    }

    override func layout() {
        super.layout()
        if let scroll = enclosingScrollView { updateVerticalAlignment(width: scroll.contentSize.width) }
    }

    override var focusRingMaskBounds: NSRect {
        guard let scroll = enclosingScrollView else { return bounds }
        return convert(scroll.bounds, from: scroll).insetBy(dx: 1, dy: 1)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill()
    }

    override func keyDown(with event: NSEvent) {
        onUserActivity?()
        if QuickChatEditorMetrics.shouldSend(keyCode: event.keyCode, modifiers: event.modifierFlags, markedText: hasMarkedText()) {
            send?(); return
        }
        super.keyDown(with: event)
    }
}

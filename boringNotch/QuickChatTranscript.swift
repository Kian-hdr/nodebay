import AppKit

/// Native selectable text per message. Appending an answer leaves earlier text
/// views intact, preserving their selection and the reader's scroll position.
final class QuickChatTranscriptDocumentView: NSView {
    override var isFlipped: Bool { true }
    private(set) var rows: [QuickChatMessageRow] = []
    var focusChanged: ((Bool) -> Void)?
    var interactionChanged: ((Bool) -> Void)?
    var onUserActivity: (() -> Void)?
    var latestStateChanged: ((Bool) -> Void)?
    var reduceMotion = false
    private var arranging = false
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?
    private var followingLatest = true
    private var unreadLatest = false {
        didSet { if unreadLatest != oldValue { latestStateChanged?(unreadLatest) } }
    }
    private var adjustingScroll = false

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    func attach(to scroll: NSScrollView) {
        guard observedClipView !== scroll.contentView else { return }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        let clip = scroll.contentView
        observedClipView = clip
        clip.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportChanged() }
        }
    }

    func update(_ entries: [QuickChatMessage], render: (String) -> NSAttributedString) {
        guard entries.count != rows.count || !zip(entries, rows).allSatisfy({ $0.1.matches($0.0) }) else { return }
        let scroll = enclosingScrollView
        let origin = scroll?.contentView.bounds.origin ?? .zero
        let wasFollowing = followingLatest && isNearLatest(in: scroll)
        let selecting = rows.contains { $0.textView.selectedRange().length > 0 }
        while rows.count > entries.count { rows.removeLast().removeFromSuperview() }
        for (index, message) in entries.enumerated() {
            if index == rows.count {
                let row = QuickChatMessageRow()
                row.textView.focusChanged = { [weak self] in self?.focusChanged?($0) }
                row.textView.interactionChanged = { [weak self] in self?.interactionChanged?($0) }
                row.textView.onUserActivity = { [weak self] in self?.onUserActivity?() }
                rows.append(row); addSubview(row)
            }
            rows[index].update(message, render: render)
        }
        arrangeRows()
        if let scroll {
            if wasFollowing && !selecting {
                jumpToLatest(animated: false)
            } else {
                let maximum = max(0, bounds.height - scroll.contentSize.height)
                setScrollOrigin(NSPoint(x: origin.x, y: min(maximum, origin.y)), in: scroll, animated: false)
                followingLatest = isNearLatest(in: scroll) && !selecting
                unreadLatest = !followingLatest
            }
        }
    }

    func jumpToLatest(animated: Bool = true) {
        guard let scroll = enclosingScrollView else { return }
        let point = NSPoint(x: scroll.contentView.bounds.origin.x,
                            y: max(0, bounds.height - scroll.contentSize.height))
        setScrollOrigin(point, in: scroll, animated: animated && !reduceMotion)
        followingLatest = true
        unreadLatest = false
    }

    private func isNearLatest(in scroll: NSScrollView?) -> Bool {
        guard let scroll else { return rows.isEmpty }
        return bounds.height <= scroll.contentSize.height || scroll.documentVisibleRect.maxY >= bounds.maxY - 24
    }

    private func viewportChanged() {
        guard !adjustingScroll, let scroll = enclosingScrollView else { return }
        followingLatest = isNearLatest(in: scroll)
        if followingLatest { unreadLatest = false }
        onUserActivity?()
    }

    private func setScrollOrigin(_ point: NSPoint, in scroll: NSScrollView, animated: Bool) {
        adjustingScroll = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                scroll.contentView.animator().setBoundsOrigin(point)
            } completionHandler: { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                self.adjustingScroll = false
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        } else {
            scroll.contentView.scroll(to: point)
            scroll.reflectScrolledClipView(scroll.contentView)
            adjustingScroll = false
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changedWidth = frame.width != newSize.width
        super.setFrameSize(newSize)
        if changedWidth { arrangeRows() }
    }

    private func arrangeRows() {
        guard !arranging, bounds.width > 6 else { return }
        arranging = true; defer { arranging = false }
        var y: CGFloat = 4
        for row in rows {
            let height = row.height(for: max(1, bounds.width - 6))
            row.frame = NSRect(x: 3, y: y, width: max(1, bounds.width - 6), height: height)
            y += height + 10
        }
        setFrameSize(NSSize(width: frame.width, height: max(0, y - 6)))
    }
}

final class QuickChatMessageRow: NSView {
    override var isFlipped: Bool { true }
    let textView = QuickChatFocusableTextView()
    private var message: QuickChatMessage?
    private(set) var bubbleFrame = NSRect.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isEditable = false; textView.isSelectable = true; textView.isRichText = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false; textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        addSubview(textView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func matches(_ other: QuickChatMessage) -> Bool { message?.role == other.role && message?.text == other.text }

    func update(_ message: QuickChatMessage, render: (String) -> NSAttributedString) {
        guard !matches(message) else { return }
        let selection = textView.selectedRange()
        self.message = message
        textView.setAccessibilityLabel(message.role == .user ? "Your message" : "Codex reply")
        let content = message.role == .user ? NSAttributedString(string: message.text, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
        ]) : render(message.text)
        textView.textStorage?.setAttributedString(content)
        if selection.length > 0 {
            let maximum = textView.string.utf16.count
            let location = min(selection.location, maximum)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, maximum - location)))
        }
        needsDisplay = true
    }

    func height(for width: CGFloat) -> CGFloat {
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return 0 }
        let isUser = message?.role == .user
        let horizontal: CGFloat = isUser ? 8 : 0
        let vertical: CGFloat = isUser ? 5 : 3
        let maximum = isUser ? width * 0.78 : width
        container.containerSize = NSSize(width: max(1, maximum - horizontal * 2), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        // NSTextView's used rect can expand to the container after resizing.
        // Measure the attributed text independently, including explicit lines.
        let measured = textView.attributedString().boundingRect(
            with: container.containerSize, options: [.usesLineFragmentOrigin, .usesFontLeading])
        let natural = ceil(measured.width) + horizontal * 2
        let textWidth = isUser ? min(maximum, max(32, natural)) : width
        container.containerSize.width = max(1, textWidth - horizontal * 2)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).maxY) + vertical * 2
        let x = isUser ? width - textWidth : 0
        textView.textContainerInset = NSSize(width: horizontal, height: vertical)
        textView.frame = NSRect(x: x, y: 0, width: textWidth, height: height)
        bubbleFrame = isUser ? textView.frame : .zero
        needsDisplay = true
        return height
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !bubbleFrame.isEmpty else { return }
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bubbleFrame, xRadius: 8, yRadius: 8).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

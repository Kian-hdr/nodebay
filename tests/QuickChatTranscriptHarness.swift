import AppKit

@main struct QuickChatTranscriptHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        let document = QuickChatTranscriptDocumentView(frame: NSRect(x: 0, y: 0, width: 500, height: 0))
        scroll.documentView = document
        document.attach(to: scroll)
        var latestStates: [Bool] = []
        document.latestStateChanged = { latestStates.append($0) }
        func render(_ text: String) -> NSAttributedString { NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]) }
        var entries = [QuickChatMessage(role: .user, text: "Hello"), QuickChatMessage(role: .assistant, text: "A synthetic answer.")]
        document.update(entries, render: render)
        let first = document.rows[0]
        precondition(first.bubbleFrame.minX > 0 && first.bubbleFrame.width <= first.bounds.width * 0.78)
        precondition(abs(first.bubbleFrame.maxX - first.bounds.maxX) < 0.5)
        precondition(document.rows[1].bubbleFrame.isEmpty && document.rows[1].textView.frame.minX == 0)
        precondition(first.textView.isSelectable && !first.textView.isEditable && !first.textView.drawsBackground)
        precondition(first.textView.accessibilityLabel() == "Your message")
        precondition(document.rows[1].textView.accessibilityLabel() == "Codex reply")

        // Opening/resizing the notch must not stretch a short bubble to its cap.
        let greetingWidth = first.bubbleFrame.width
        precondition(greetingWidth < 100)
        for width: CGFloat in [320, 560, 240, 500] {
            document.setFrameSize(NSSize(width: width, height: document.frame.height))
            precondition(abs(first.bubbleFrame.width - greetingWidth) < 1)
            precondition(abs(first.bubbleFrame.maxX - first.bounds.maxX) < 0.5)
        }

        let sizingRow = QuickChatMessageRow()
        for text in ["Hi", "A short message", "First line\nSecond line", "日本語 👋🏽", "مرحبا",
                     String(repeating: "A longer message that wraps naturally. ", count: 12),
                     String(repeating: "abcdefghij", count: 40)] {
            sizingRow.update(.init(role: .user, text: text), render: render)
            for width: CGFloat in [500, 240, 560, 320] {
                let height = sizingRow.height(for: width)
                precondition(sizingRow.bubbleFrame.width <= width * 0.78)
                precondition(abs(sizingRow.bubbleFrame.maxX - width) < 0.5)
                precondition(height > 0 && height.isFinite)
                if text.count < 30 { precondition(sizingRow.bubbleFrame.width < 140) }
                if text.contains("\n") || text.count > 100 { precondition(height > first.frame.height) }
            }
        }

        // Incremental content follows only while the reader is near the bottom.
        entries[1] = .init(role: .assistant, text: String(repeating: "Streaming answer line\n", count: 20))
        document.update(entries, render: render)
        precondition(abs(scroll.documentVisibleRect.maxY - document.bounds.maxY) < 1)
        entries[1] = .init(role: .assistant, text: entries[1].text + String(repeating: "More visible text\n", count: 8))
        document.update(entries, render: render)
        precondition(abs(scroll.documentVisibleRect.maxY - document.bounds.maxY) < 1)

        // A selected range survives an incremental update and prevents a yank.
        document.rows[1].textView.setSelectedRange(NSRange(location: 0, length: 9))
        let selectedOrigin = scroll.contentView.bounds.origin
        entries[1] = .init(role: .assistant, text: entries[1].text + "Completed suffix")
        document.update(entries, render: render)
        precondition(document.rows[1].textView.selectedRange().length == 9)
        precondition(abs(scroll.contentView.bounds.origin.y - selectedOrigin.y) < 1)
        precondition(latestStates.last == true)
        document.rows[1].textView.setSelectedRange(NSRange(location: 0, length: 0))

        // Jumping is immediate under Reduce Motion and resumes following.
        document.reduceMotion = true
        document.jumpToLatest(animated: true)
        precondition(abs(scroll.documentVisibleRect.maxY - document.bounds.maxY) < 1)
        precondition(latestStates.last == false)
        entries.append(.init(role: .assistant, text: "A newly completed answer"))
        document.update(entries, render: render)
        precondition(abs(scroll.documentVisibleRect.maxY - document.bounds.maxY) < 1)

        // Intentional scroll-up is retained across a long appended reply.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 20))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        let readerOrigin = scroll.contentView.bounds.origin.y
        entries.append(.init(role: .assistant, text: String(repeating: "Long unread reply\n", count: 60)))
        document.update(entries, render: render)
        precondition(abs(scroll.contentView.bounds.origin.y - readerOrigin) < 1)
        precondition(latestStates.last == true)

        // Scrolling back to the bottom manually resumes automatic following.
        let bottom = max(0, document.bounds.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        precondition(latestStates.last == false)
        entries.append(.init(role: .assistant, text: "Follow after returning to bottom"))
        document.update(entries, render: render)
        precondition(abs(scroll.documentVisibleRect.maxY - document.bounds.maxY) < 1)

        // The explicit affordance is immediate when Reduce Motion is enabled.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 20))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        document.reduceMotion = true
        document.jumpToLatest(animated: false)
        precondition(latestStates.last == false)

        first.textView.setSelectedRange(NSRange(location: 0, length: 3))
        entries += [.init(role: .user, text: String(repeating: "日本語 code long message ", count: 60)),
                    .init(role: .assistant, text: String(repeating: "Long answer\n", count: 60))]
        document.update(entries, render: render)
        precondition(document.rows[0] === first && first.textView.selectedRange().length == 3)
        precondition(document.rows[2].bubbleFrame.width <= document.rows[2].bounds.width * 0.78)
        precondition(document.bounds.height > scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 20))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        entries.append(.init(role: .assistant, text: "An appended answer"))
        document.update(entries, render: render)
        precondition(abs(scroll.contentView.bounds.origin.y - 20) < 1)
        document.setFrameSize(NSSize(width: 320, height: document.frame.height))
        precondition(document.rows[2].bubbleFrame.width <= document.rows[2].bounds.width * 0.78)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            document.appearance = NSAppearance(named: appearance)
            precondition(!document.rows[0].textView.drawsBackground)
        }
        precondition(!QuickChatPolicy.allowsNotchPan(isOpen: true, chatSelected: true))
        precondition(QuickChatPolicy.allowsNotchPan(isOpen: true, chatSelected: false))
        precondition(QuickChatPolicy.allowsNotchPan(isOpen: false, chatSelected: true))
        print("Native chat bubble sizing, sender semantics, selection, scrolling and pan routing passed")
    }
}

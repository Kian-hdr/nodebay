import AppKit
import SwiftUI

@main struct QuickChatComposerHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let metrics = QuickChatEditorMetrics.self
        let single = metrics.height(for: "Hello", width: 400)
        let wrapped = metrics.height(for: String(repeating: "word ", count: 25), width: 180)
        precondition(single == metrics.minimumHeight)
        precondition(metrics.height(for: "", width: 400) == single)
        precondition(metrics.minimumHeight == 24)
        let centered = metrics.layout(for: "Hello", width: 400)
        precondition(centered.height == 24 && centered.verticalInset > 2)
        precondition(metrics.layout(for: "", width: 400).verticalInset == centered.verticalInset)
        precondition(metrics.layout(for: String(repeating: "line\n", count: 100), width: 400).verticalInset == 2)
        precondition(metrics.height(for: "Hello\n", width: 400) > single)
        precondition(wrapped > single && wrapped <= metrics.maximumHeight)
        precondition(metrics.height(for: String(repeating: "line\n", count: 100), width: 400) == metrics.maximumHeight)
        precondition(metrics.height(for: "日本語 🦉 مرحبا", width: 150).isFinite)
        precondition(metrics.shouldSend(keyCode: 36, modifiers: [], markedText: false))
        precondition(metrics.shouldSend(keyCode: 76, modifiers: [.capsLock], markedText: false))
        for modifier: NSEvent.ModifierFlags in [.shift, .control, .option, .command] {
            precondition(!metrics.shouldSend(keyCode: 36, modifiers: modifier, markedText: false))
        }
        precondition(!metrics.shouldSend(keyCode: 36, modifiers: [], markedText: true))
        precondition(!metrics.shouldSend(keyCode: 48, modifiers: [], markedText: false))
        let host = NSHostingView(rootView: QuickChatComposer(text: .constant("Hello"), editing: .constant(false),
            canSend: true, generating: false, send: {}, stop: {}))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 32)
        host.layoutSubtreeIfNeeded()
        func textView(_ view: NSView) -> QuickChatTextView? {
            if let text = view as? QuickChatTextView { return text }
            return view.subviews.lazy.compactMap(textView).first
        }
        guard let editor = textView(host), let scroll = editor.enclosingScrollView else { fatalError("Native editor missing") }
        precondition(!editor.drawsBackground && !scroll.drawsBackground)
        precondition(scroll.borderType == .noBorder && scroll.autohidesScrollers)
        precondition(editor.allowsUndo && !editor.isRichText)
        precondition(editor.focusRingType == .exterior)
        for sample in ["", "Hello", "日本語 🦉", "Two\nlines", String(repeating: "long line\n", count: 20)] {
            editor.string = sample
            editor.updateVerticalAlignment(width: 400)
            precondition(editor.textContainerInset.height == metrics.layout(for: sample, width: 400).verticalInset)
        }
        editor.string = "Hello"
        editor.updateVerticalAlignment(width: 400)
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        let line = editor.layoutManager!.usedRect(for: editor.textContainer!)
        // AppKit rounds the text origin to the backing pixel grid.
        precondition(abs(editor.textContainerOrigin.y + line.midY - metrics.minimumHeight / 2) <= 0.5,
                     "origin=\(editor.textContainerOrigin.y), line=\(line), inset=\(editor.textContainerInset), frame=\(editor.frame)")
        var interactions: [Bool] = []
        editor.interactionChanged = { interactions.append($0) }
        _ = editor.becomeFirstResponder()
        precondition(interactions.isEmpty) // Mere keyboard focus never locks the notch open.
        editor.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(interactions.last == true)
        editor.unmarkText()
        precondition(interactions.last == false)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            host.appearance = NSAppearance(named: name)
            host.layoutSubtreeIfNeeded()
            precondition(!editor.drawsBackground && !scroll.drawsBackground)
        }
        print("Native composer: transparent editor, semantic appearances, wrapping, height cap and keyboard policy passed")
    }
}

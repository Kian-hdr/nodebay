// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import NodebayMarkdown

@main
struct MarkdownPreviewBackgroundHarness {
    @MainActor
    static func main() {
        // Build actual AppKit views without opening a window or changing system settings.
        _ = NSApplication.shared
        let suite = "NodebayPreviewBackgroundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = PreviewViewController()
        controller.loadViewIfNeeded()
        let scroll = controller.view as! NSScrollView
        let text = scroll.documentView as! NSTextView
        let key = "markdownPreviewSolidBackground"
        let reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        controller.applyBackgroundPreference(defaults: defaults)
        precondition(scroll.drawsBackground, "A fresh install must use a solid background")
        precondition(!text.drawsBackground && text.isSelectable && !text.isEditable)

        text.string = "A selectable Markdown document"
        let selection = NSRange(location: 2, length: 10)
        text.setSelectedRange(selection)
        defaults.set(true, forKey: key)
        controller.applyBackgroundPreference(defaults: defaults)
        precondition(scroll.drawsBackground, "Enabled preference must fill the document viewport")
        precondition(scroll.backgroundColor == .windowBackgroundColor, "Solid background must use adaptive system window color")
        precondition(text.selectedRange() == selection && text.string == "A selectable Markdown document")
        precondition(!text.drawsBackground, "Text must not introduce a second document surface")

        // A second defaults/controller instance reads the persisted choice.
        let reopened = PreviewViewController()
        reopened.loadViewIfNeeded()
        reopened.applyBackgroundPreference(defaults: UserDefaults(suiteName: suite)!)
        let reopenedScroll = reopened.view as! NSScrollView
        precondition(reopenedScroll.drawsBackground)
        let emptyText = reopenedScroll.documentView as! NSTextView
        precondition(emptyText.string.isEmpty)
        precondition(reopenedScroll.bounds.width > 0 && reopenedScroll.bounds.height > 0)
        precondition(!emptyText.drawsBackground, "Empty documents use the full scroll viewport backing")

        defaults.set(false, forKey: key)
        controller.applyBackgroundPreference(defaults: defaults)
        precondition(scroll.drawsBackground == reducedTransparency, "Disabling must restore glass when accessibility allows it")
        precondition(text.selectedRange() == selection)
        precondition(!text.drawsBackground && text.isSelectable && !text.isEditable)
        let reopenedGlass = PreviewViewController()
        reopenedGlass.loadViewIfNeeded()
        reopenedGlass.applyBackgroundPreference(defaults: UserDefaults(suiteName: suite)!)
        precondition((reopenedGlass.view as! NSScrollView).drawsBackground == reducedTransparency,
                     "A saved off choice must override the new-install default")
        print("Markdown preview background checks passed (Reduce Transparency: \(reducedTransparency))")
    }
}

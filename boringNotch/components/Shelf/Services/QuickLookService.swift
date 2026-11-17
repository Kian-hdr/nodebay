//
//  QuickLookService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import SwiftUI
import QuickLookUI
import AppKit

@MainActor
final class QuickLookService: ObservableObject {
    @Published private(set) var urls: [URL] = []
    @Published var selectedURL: URL? {
        didSet {
            // SwiftUI clears the selection when the system preview is dismissed.
            if selectedURL == nil, isQuickLookOpen {
                endPreview()
            }
        }
    }
    @Published private(set) var isQuickLookOpen = false

    private weak var previewPanel: QLPreviewPanel?
    private var scopedURLs: [URL] = []

    func show(urls: [URL], selectFirst: Bool = true) {
        var newScopes: [URL] = []
        let readableURLs = urls.filter { url in
            guard url.isFileURL else { return true }
            let scoped = url.startAccessingSecurityScopedResource()
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                return false
            }
            if scoped { newScopes.append(url) }
            return true
        }
        guard !readableURLs.isEmpty else { return }

        // Maintain access during a selection change, including files present in both lists.
        let previousScopes = scopedURLs
        scopedURLs = newScopes
        urlsDidChange(to: readableURLs, selectFirst: selectFirst)
        previousScopes.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private func urlsDidChange(to readableURLs: [URL], selectFirst: Bool) {
        if previewPanel == nil, let panel = QLPreviewPanel.shared() {
            previewPanel = panel
            NotificationCenter.default.addObserver(
                self, selector: #selector(previewPanelWillClose(_:)),
                name: NSWindow.willCloseNotification, object: panel
            )
        }
        urls = readableURLs
        isQuickLookOpen = true
        if selectFirst { selectedURL = readableURLs.first }
    }

    func hide() {
        let panel = previewPanel
        endPreview()
        if panel?.isVisible == true { panel?.orderOut(nil) }
    }

    private func endPreview() {
        if let panel = previewPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            previewPanel = nil
        }
        isQuickLookOpen = false
        if selectedURL != nil { selectedURL = nil }
        urls.removeAll()
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs.removeAll()
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
        show(urls: urls)
    }

    @objc private func previewPanelWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel, panel === previewPanel else { return }
        endPreview()
    }
}

struct QuickLookPresenter: ViewModifier {
    @ObservedObject var service: QuickLookService

    func body(content: Content) -> some View {
        content
            .quickLookPreview($service.selectedURL, in: service.urls)
    }
}

extension View {
    func quickLookPresenter(using service: QuickLookService) -> some View {
        self.modifier(QuickLookPresenter(service: service))
    }
}


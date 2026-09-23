// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import WebKit

/// Converts untrusted Mermaid text to a static local attachment, never a browsable web view.
/// Await calls serially. A fresh nonpersistent web view isolates every diagram and its errors.
@MainActor
final class MermaidDiagramRenderer: NSObject, WKNavigationDelegate {
    enum RenderError: Error {
        case unavailable, tooComplex, busy, timedOut, invalidOutput
    }

    private struct Request {
        let id: UUID
        let source: String
        let dark: Bool
        let continuation: CheckedContinuation<NSImage, Error>
    }

    private var request: Request?
    private var webView: WKWebView?
    private var timeout: Task<Void, Never>?
    private var documentURL: URL?
    private var networkRules: WKContentRuleList?

    func render(_ source: String, dark: Bool) async throws -> NSImage {
        try Task.checkCancellation()
        guard request == nil else { throw RenderError.busy }
        guard source.utf8.count <= 20_000, source.split(separator: "\n", omittingEmptySubsequences: false).count <= 300 else {
            throw RenderError.tooComplex
        }
        guard let url = Bundle.main.url(forResource: "renderer", withExtension: "html", subdirectory: "Mermaid") else {
            throw RenderError.unavailable
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request = Request(id: id, source: source, dark: dark, continuation: continuation)
                documentURL = url
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                configuration.suppressesIncrementalRendering = true
                // CSP in the bundled page blocks all network subresources. Navigation is
                // restricted below; no document-derived URL is ever loaded by this helper.
                let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), configuration: configuration)
                web.navigationDelegate = self
                webView = web
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    self?.finish(id: id, result: .failure(RenderError.timedOut))
                }
                if let networkRules {
                    web.configuration.userContentController.add(networkRules)
                    web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                } else {
                    let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]"#
                    WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: "NodebayMermaidNoNetwork-v1", encodedContentRuleList: rules
                    ) { [weak self, weak web] list, error in
                        guard let self, let web, self.request?.id == id else { return }
                        guard let list else {
                            self.finish(id: id, result: .failure(error ?? RenderError.unavailable))
                            return
                        }
                        self.networkRules = list
                        web.configuration.userContentController.add(list)
                        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(id: id, result: .failure(CancellationError()))
            }
        }
    }

    func cancel() {
        guard let id = request?.id else { return }
        finish(id: id, result: .failure(CancellationError()))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, let current = request else { return }
        webView.callAsyncJavaScript(
            "return await window.nodebayRenderDiagram(source, dark);",
            arguments: ["source": current.source, "dark": current.dark],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.request?.id == current.id else { return }
            do {
                let value = try result.get()
                guard let dictionary = value as? [String: Any],
                      let base64 = dictionary["png"] as? String, base64.count <= 24_000_000,
                      let width = dictionary["width"] as? Double,
                      let height = dictionary["height"] as? Double,
                      width.isFinite, height.isFinite, width > 0, height > 0,
                      width <= 20_000, height <= 20_000,
                      let data = Data(base64Encoded: base64),
                      let image = NSImage(data: data) else { throw RenderError.invalidOutput }
                image.size = NSSize(width: width, height: height)
                self.finish(id: current.id, result: .success(image))
            } catch {
                self.finish(id: current.id, result: .failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let permitted = webView === self.webView
            && navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.request.url?.standardizedFileURL == documentURL?.standardizedFileURL
            && navigationAction.navigationType == .other
        decisionHandler(permitted ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, let id = request?.id else { return }
        finish(id: id, result: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView, let id = request?.id else { return }
        finish(id: id, result: .failure(RenderError.unavailable))
    }

    private func finish(id: UUID, result: Result<NSImage, Error>) {
        guard let current = request, current.id == id else { return }
        request = nil
        timeout?.cancel()
        timeout = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        documentURL = nil
        current.continuation.resume(with: result)
    }
}

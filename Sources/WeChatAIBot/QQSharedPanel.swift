#if canImport(SwiftUI) && canImport(WebKit)
import SwiftUI
import WebKit

/// A native window can attach to a QQ worker already owned by another client/MCP Host.
struct QQSharedPanel: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(origin: url) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let origin: URL
        init(origin: URL) { self.origin = origin }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port {
                decisionHandler(.allow)
            } else {
                if navigationAction.navigationType == .linkActivated, url.scheme == "https" { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            }
        }
    }
}

@MainActor func pauseSharedQQ(_ url: URL) {
    guard let token = url.fragment, url.scheme == "http", url.host == "127.0.0.1", let port = url.port else { return }
    let origin = "http://127.0.0.1:\(port)"
    var request = URLRequest(url: URL(string: origin + "/api/action")!)
    request.httpMethod = "POST"; request.timeoutInterval = 10
    request.setValue(token, forHTTPHeaderField: "X-QQ-Control")
    request.setValue(origin, forHTTPHeaderField: "Origin")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{\"action\":\"pause\"}".utf8)
    Task { _ = try? await URLSession.shared.data(for: request) }
}
#endif

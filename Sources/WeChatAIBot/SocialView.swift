#if os(macOS)
import SwiftUI
import WebKit
private typealias SocialViewState<Value> = SwiftUI.State<Value>

/// The native and browser panels deliberately load the same controls and engine.
struct SocialView: View {
    @ObservedObject var engine: SocialEngine
    let workspace: SocialPlatforms
    @SocialViewState private var server: SocialControlServer?
    @SocialViewState private var failure = ""
    var body: some View {
        VStack(spacing: 0) {
            if let server {
                HStack {
                    Spacer()
                    Button("在浏览器打开") { NSWorkspace.shared.open(url(server)) }
                        .buttonStyle(PanelButtonStyle()).padding(.horizontal, 26).padding(.vertical, 10)
                }
                SocialWebView(url: url(server), platform: engine.platform).id(engine.platform)
            } else if !failure.isEmpty { Text(failure).padding() }
            else { ProgressView().padding() }
        }
        .task {
            guard server == nil else { return }
            do { server = try workspace.panel() }
            catch { failure = error.localizedDescription }
        }
        // Closing an app window must not invalidate an external tab still in use.
    }
    private func url(_ server: SocialControlServer) -> URL {
        var components = URLComponents(url: server.controlURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "platform", value: engine.platform.rawValue)]
        return components.url!
    }
}
private struct SocialWebView: NSViewRepresentable {
    let url: URL
    let platform: SocialPlatform
    func makeCoordinator() -> Coordinator { Coordinator(platform: platform) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = context.coordinator; view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url)); return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let platform: SocialPlatform
        init(platform: SocialPlatform) { self.platform = platform }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert(); alert.messageText = "请确认操作"; alert.informativeText = message
            alert.addButton(withTitle: "确认"); alert.addButton(withTitle: "取消")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "https", platform.hosts.contains(url.host ?? "") {
                NSWorkspace.shared.open(url); decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.request.url?.host == "127.0.0.1" ? .allow : .cancel) }
        }
    }
}
#endif

import SwiftUI
import WebKit

/// WKWebView 的 SwiftUI 包装。
/// 职责：把 ViewModel 的加载指令应用到网页，并把导航事件回传给 ViewModel。
/// 网页引擎由 WKWebView（框架层）提供；ViewModel 不直接接触 WKWebView。
struct WebViewRepresentable: UIViewRepresentable {
    let viewModel: BrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = viewModel.requestedLoad {
            webView.load(URLRequest(url: url))
            viewModel.consumeRequestedLoad()
        }
        switch viewModel.pendingCommand {
        case .none:
            break
        case .goBack:
            webView.goBack()
        case .goForward:
            webView.goForward()
        case .reload:
            webView.reload()
        }
        viewModel.consumeCommand()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private let viewModel: BrowserViewModel

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            let url = webView.url
            viewModel.webViewDidStartProvisionalNavigation(url: url)
            viewModel.updateNavigationButtons(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url
            let title = webView.title
            viewModel.webViewDidFinishNavigation(url: url, title: title)
            viewModel.updateNavigationButtons(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.webViewDidFailNavigation(url: webView.url, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel.webViewDidFailNavigation(url: webView.url, error: error)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // target=_blank 链接在当前页打开，避免丢失会话。
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

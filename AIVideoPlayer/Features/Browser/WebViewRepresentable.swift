import SwiftUI
import WebKit

/// WKWebView 的 SwiftUI 包装。
/// 职责：把 ViewModel 的加载指令应用到网页，并把导航事件回传给 ViewModel。
/// 网页引擎由 WKWebView（框架层）提供；ViewModel 不直接接触 WKWebView。
struct WebViewRepresentable: UIViewRepresentable {
    let viewModel: BrowserViewModel
    /// 命令版本号：作为输入值让 SwiftUI 在命令变化时调用 `updateUIView`。
    let commandVersion: Int
    /// 网页内检测到可直接播放的视频时回调（直链导航 / HTML5 video 播放）。
    var onVideoDetected: (URL, String?) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onVideoDetected: onVideoDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 视频默认在页面内联播放，避免跳转到系统全屏播放器；
        // 可直连的媒体由桥接脚本 / 导航拦截转交给内置播放器。
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.userContentController.add(context.coordinator, name: "aiVideoPlay")
        configuration.userContentController.addUserScript(Self.videoBridgeScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
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
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let viewModel: BrowserViewModel
        private let onVideoDetected: (URL, String?) -> Void

        init(viewModel: BrowserViewModel, onVideoDetected: @escaping (URL, String?) -> Void) {
            self.viewModel = viewModel
            self.onVideoDetected = onVideoDetected
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

        /// 拦截直接媒体链接（.mp4 / .m3u8 / 音频等）：取消网页内系统播放，
        /// 转交给内置播放器；其余导航照常放行。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               BrowserViewModel.isDirectlyPlayable(url: url) {
                onVideoDetected(url, nil)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// HTML5 video 播放桥接：页面内 `<video>` 尝试播放可直连媒体时，
        /// 由脚本上报 URL，此处转交给内置播放器。
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "aiVideoPlay",
                  let body = message.body as? [String: Any],
                  let urlString = body["url"] as? String,
                  let url = URL(string: urlString) else {
                return
            }
            let title = body["title"] as? String
            onVideoDetected(url, title)
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

    /// 注入页面：拦截可直连媒体的 HTML5 video 播放，上报 App 由内置播放器接管；
    /// blob: / data: 等不可直连来源保持页面内联播放（`allowsInlineMediaPlayback`）。
    private static let videoBridgeScript = WKUserScript(
        source: """
        (function () {
          if (window.__aiVideoPlayerBridgeInstalled) { return; }
          window.__aiVideoPlayerBridgeInstalled = true;

          var gesture = false;
          document.addEventListener('click', function () {
            gesture = true;
            setTimeout(function () { gesture = false; }, 100);
          }, true);

          function report(element) {
            var src = element.currentSrc || element.src || '';
            if (!/^https?:\\/\\//i.test(src)) { return false; }
            var title = element.getAttribute('title') ||
                        element.getAttribute('aria-label') || '';
            if (!title && element.closest) {
              var link = element.closest('a');
              if (link) { title = link.getAttribute('title') || title; }
            }
            if (!title) { title = document.title || ''; }
            try {
              window.webkit.messageHandlers.aiVideoPlay.postMessage({
                url: src,
                title: title
              });
              return true;
            } catch (e) {
              return false;
            }
          }

          var originalPlay = HTMLMediaElement.prototype.play;
          HTMLMediaElement.prototype.play = function () {
            if (this.tagName === 'VIDEO' &&
                (gesture || this.controls) &&
                report(this)) {
              return Promise.resolve();
            }
            return originalPlay.apply(this, arguments);
          };

          document.addEventListener('click', function (event) {
            var element = event.target;
            var video = (element && element.closest) ? element.closest('video') : null;
            if (video && video.paused && report(video)) {
              event.preventDefault();
              event.stopPropagation();
            }
          }, true);
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )
}

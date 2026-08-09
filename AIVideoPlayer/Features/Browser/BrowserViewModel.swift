import Foundation
import Observation

/// 网页引擎（WKWebView）指令，由 WebViewRepresentable 消费。
enum WebViewCommand: Equatable {
    case none
    case goBack
    case goForward
    case reload
}

/// 浏览器导航状态：URL 解析、网页加载状态、历史与收藏。
/// 网页引擎 WKWebView 作为 UI 组件由 WebViewRepresentable 管理，
/// 事件经其回调回到本 VM；VM 不直接接触网络。
@MainActor
@Observable
final class BrowserViewModel {
    enum NavigationState: Equatable {
        case idle
        case loading(URL)
        case ready(URL)
        case failed(URL, String)
    }

    private(set) var navigationState: NavigationState = .idle
    var addressText = ""
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var pendingCommand: WebViewCommand = .none
    /// 命令版本号：每次设置 pendingCommand 时递增，供 WebViewRepresentable
    /// 作为输入参数触发 `updateUIView`（SwiftUI 不会因为 class 内部属性变化
    /// 自动刷新代表视图，必须先让 View body 观察到变化）。
    private(set) var commandVersion = 0
    private(set) var requestedLoad: URL?
    private(set) var history: [BrowserHistoryEntry] = []
    private(set) var bookmarks: [Bookmark] = []
    private(set) var extractedMedia: LoadState<[MediaItem]> = .loading

    private let historyStore: any BrowserHistoryStoring
    private let bookmarkStore: any BookmarkStoring
    private let mediaExtractor: any MediaExtractor

    private var extractionGeneration = 0
    private var extractionTask: Task<Void, Never>?

    init(
        historyStore: any BrowserHistoryStoring = UserDefaultsHistoryStore(),
        bookmarkStore: any BookmarkStoring = UserDefaultsBookmarkStore(),
        mediaExtractor: any MediaExtractor = WebMediaExtractor()
    ) {
        self.historyStore = historyStore
        self.bookmarkStore = bookmarkStore
        self.mediaExtractor = mediaExtractor
        self.history = historyStore.loadEntries()
        self.bookmarks = bookmarkStore.loadBookmarks()
    }

    var isLoading: Bool {
        if case .loading = navigationState { return true }
        return false
    }

    var isWebContentVisible: Bool {
        if case .idle = navigationState { return false }
        return true
    }

    var currentURL: URL? {
        switch navigationState {
        case .loading(let url), .ready(let url):
            return url
        case .idle, .failed:
            return nil
        }
    }

    var isCurrentPageBookmarked: Bool {
        guard let currentURL else { return false }
        return bookmarks.contains { $0.url == currentURL }
    }

    // MARK: - 地址栏

    /// 解析地址栏输入并开始加载。
    func submitAddress(_ text: String) {
        guard let url = Self.makeURL(from: text) else { return }
        load(url)
    }

    /// 加载 URL（地址栏 / 历史 / 收藏共用入口）。
    func load(_ url: URL) {
        addressText = url.absoluteString
        navigationState = .loading(url)
        requestedLoad = url
    }

    func goBack() {
        pendingCommand = .goBack
        commandVersion += 1
    }

    func goForward() {
        pendingCommand = .goForward
        commandVersion += 1
    }

    func reload() {
        pendingCommand = .reload
        commandVersion += 1
    }

    func consumeCommand() {
        pendingCommand = .none
    }

    func consumeRequestedLoad() {
        requestedLoad = nil
    }

    private static func makeURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    // MARK: - WKWebView 回调（由 WebViewRepresentable 转发，均在主线程）

    func webViewDidStartProvisionalNavigation(url: URL?) {
        if let url {
            navigationState = .loading(url)
            addressText = url.absoluteString
        }
    }

    func webViewDidFinishNavigation(url: URL?, title: String?) {
        if let url {
            navigationState = .ready(url)
            addressText = url.absoluteString
            recordHistory(url: url, title: title)
        }
    }

    func webViewDidFailNavigation(url: URL?, error: Error) {
        if let url {
            navigationState = .failed(url, error.localizedDescription)
        }
    }

    func updateNavigationButtons(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    // MARK: - 历史 / 收藏

    func openHistoryEntry(_ entry: BrowserHistoryEntry) {
        load(entry.url)
    }

    func openBookmark(_ bookmark: Bookmark) {
        load(bookmark.url)
    }

    func toggleBookmarkForCurrentPage() {
        guard let url = currentURL else { return }
        if let existing = bookmarks.first(where: { $0.url == url }) {
            try? bookmarkStore.removeBookmark(id: existing.id)
        } else {
            let title = Self.title(for: url, fallback: addressText)
            try? bookmarkStore.addBookmark(Bookmark(url: url, title: title))
        }
        bookmarks = bookmarkStore.loadBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        try? bookmarkStore.removeBookmark(id: bookmark.id)
        bookmarks = bookmarkStore.loadBookmarks()
    }

    func clearHistory() {
        try? historyStore.clear()
        history = historyStore.loadEntries()
    }

    // MARK: - 媒体提取（Phase 4）

    /// 提取当前页面 / 直链媒体并更新 `extractedMedia`（五态）。
    /// 新提取会取消旧任务；generation 防止过期结果覆盖当前页面。
    func extractMediaFromCurrentPage() async {
        guard let url = currentURL else { return }
        extractionGeneration += 1
        let currentGeneration = extractionGeneration
        extractionTask?.cancel()
        extractedMedia = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.mediaExtractor.extractMedia(from: url)
                try Task.checkCancellation()
                guard currentGeneration == self.extractionGeneration else { return }
                self.extractedMedia = items.isEmpty ? .empty : .ready(items)
            } catch {
                guard currentGeneration == self.extractionGeneration else { return }
                self.extractedMedia = Task.isCancelled ? .cancelled : .error(error.localizedDescription)
            }
        }
        extractionTask = task
        await task.value
    }

    private func recordHistory(url: URL, title: String?) {
        try? historyStore.addEntry(BrowserHistoryEntry(url: url, title: title ?? Self.title(for: url, fallback: url.host ?? url.absoluteString)))
        history = historyStore.loadEntries()
    }

    private static func title(for url: URL, fallback: String) -> String {
        fallback.isEmpty ? (url.host ?? url.absoluteString) : fallback
    }
}

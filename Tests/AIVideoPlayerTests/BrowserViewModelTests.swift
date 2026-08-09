import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct BrowserViewModelTests {

    @Test func submitAddressAddsHTTPScheme() {
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore()
        )

        viewModel.submitAddress("example.com/page")

        #expect(viewModel.addressText == "https://example.com/page")
        if case .loading(let url) = viewModel.navigationState {
            #expect(url.absoluteString == "https://example.com/page")
        } else {
            Issue.record("期望 loading 状态")
        }
    }

    @Test func submitAddressKeepsExplicitScheme() {
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore()
        )

        viewModel.submitAddress("http://example.com")

        if case .loading(let url) = viewModel.navigationState {
            #expect(url.scheme == "http")
        } else {
            Issue.record("期望 loading 状态")
        }
    }

    @Test func navigationCommandsSetPendingCommandAndBumpVersion() {
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore()
        )

        viewModel.goBack()
        #expect(viewModel.pendingCommand == .goBack)
        #expect(viewModel.commandVersion == 1)

        viewModel.goForward()
        #expect(viewModel.pendingCommand == .goForward)
        #expect(viewModel.commandVersion == 2)

        viewModel.reload()
        #expect(viewModel.pendingCommand == .reload)
        #expect(viewModel.commandVersion == 3)

        viewModel.consumeCommand()
        #expect(viewModel.pendingCommand == .none)
    }

    @Test func recordsHistoryOnFinish() throws {
        let historyStore = MockHistoryStore()
        let viewModel = BrowserViewModel(
            historyStore: historyStore,
            bookmarkStore: MockBookmarkStore()
        )
        let url = try #require(URL(string: "https://example.com"))

        viewModel.webViewDidFinishNavigation(url: url, title: "Example")

        #expect(viewModel.history.count == 1)
        #expect(viewModel.history.first?.url == url)
        #expect(viewModel.history.first?.title == "Example")
    }

    @Test func bookmarkToggleAddsAndRemoves() throws {
        let bookmarkStore = MockBookmarkStore()
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: bookmarkStore
        )
        let url = try #require(URL(string: "https://example.com"))

        viewModel.load(url)
        viewModel.toggleBookmarkForCurrentPage()
        #expect(viewModel.isCurrentPageBookmarked)
        #expect(viewModel.bookmarks.count == 1)

        viewModel.toggleBookmarkForCurrentPage()
        #expect(!viewModel.isCurrentPageBookmarked)
        #expect(viewModel.bookmarks.isEmpty)
    }

    // MARK: - Phase 4 媒体提取

    @Test func extractMediaPublishesReadyState() async throws {
        let item = try makeMediaItem(title: "Movie", urlString: "https://example.com/movie.mp4")
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore(),
            mediaExtractor: StaticMediaExtractor(result: .success([item]))
        )
        let url = try #require(URL(string: "https://example.com/watch"))
        viewModel.load(url)

        await viewModel.extractMediaFromCurrentPage()

        #expect(viewModel.extractedMedia == .ready([item]))
    }

    @Test func extractMediaPublishesEmpty() async throws {
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore(),
            mediaExtractor: StaticMediaExtractor(result: .success([]))
        )
        let url = try #require(URL(string: "https://example.com/watch"))
        viewModel.load(url)

        await viewModel.extractMediaFromCurrentPage()

        #expect(viewModel.extractedMedia == .empty)
    }

    @Test func extractMediaPublishesError() async throws {
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore(),
            mediaExtractor: StaticMediaExtractor(result: .failure(TestExtractionError()))
        )
        let url = try #require(URL(string: "https://example.com/watch"))
        viewModel.load(url)

        await viewModel.extractMediaFromCurrentPage()

        guard case .error(let message) = viewModel.extractedMedia else {
            Issue.record("期望 error 状态，实际为 \(viewModel.extractedMedia)")
            return
        }
        #expect(message == "boom")
    }

    @Test func staleExtractionResultIsDiscarded() async throws {
        let itemB = try makeMediaItem(title: "Second", urlString: "https://example.com/second.mp4")
        let extractor = GatedMediaExtractor(result: [itemB])
        let viewModel = BrowserViewModel(
            historyStore: MockHistoryStore(),
            bookmarkStore: MockBookmarkStore(),
            mediaExtractor: extractor
        )
        let urlA = try #require(URL(string: "https://example.com/first"))
        let urlB = try #require(URL(string: "https://example.com/second"))
        viewModel.load(urlA)

        let firstExtraction = Task { await viewModel.extractMediaFromCurrentPage() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.extractedMedia == .loading)

        viewModel.load(urlB)
        await viewModel.extractMediaFromCurrentPage()
        #expect(viewModel.extractedMedia == .ready([itemB]))

        extractor.openGate()
        await firstExtraction.value
        #expect(viewModel.extractedMedia == .ready([itemB]))
    }

    private func makeMediaItem(title: String, urlString: String) throws -> MediaItem {
        MediaItem(
            title: title,
            url: try #require(URL(string: urlString)),
            kind: .video,
            source: .web
        )
    }
}

private struct StaticMediaExtractor: MediaExtractor {
    let result: Result<[MediaItem], TestExtractionError>

    func extractMedia(from url: URL) async throws -> [MediaItem] {
        try result.get()
    }
}

private struct TestExtractionError: LocalizedError, Sendable {
    var errorDescription: String? { "boom" }
}

/// 第一次调用阻塞在闸门上，供过期结果测试使用；后续调用立即返回。
private final class GatedMediaExtractor: MediaExtractor, @unchecked Sendable {
    private let result: [MediaItem]
    private var isGated = true
    private var gate: CheckedContinuation<Void, Never>?

    init(result: [MediaItem]) {
        self.result = result
    }

    func openGate() {
        gate?.resume()
        gate = nil
    }

    func extractMedia(from url: URL) async throws -> [MediaItem] {
        if isGated {
            isGated = false
            await withCheckedContinuation { gate = $0 }
        }
        return result
    }
}

private final class MockHistoryStore: BrowserHistoryStoring, @unchecked Sendable {
    private var entries: [BrowserHistoryEntry] = []

    func loadEntries() -> [BrowserHistoryEntry] {
        entries
    }

    func addEntry(_ entry: BrowserHistoryEntry) throws {
        entries.insert(entry, at: 0)
    }

    func clear() throws {
        entries.removeAll()
    }
}

private final class MockBookmarkStore: BookmarkStoring, @unchecked Sendable {
    private var bookmarks: [Bookmark] = []

    func loadBookmarks() -> [Bookmark] {
        bookmarks
    }

    func addBookmark(_ bookmark: Bookmark) throws {
        bookmarks.insert(bookmark, at: 0)
    }

    func removeBookmark(id: UUID) throws {
        bookmarks.removeAll { $0.id == id }
    }
}

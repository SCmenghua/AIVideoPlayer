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

import Foundation
import Testing
@testable import AIVideoPlayer

struct HistoryBookmarkStoreTests {

    @Test func historyStoreDeduplicatesAndCaps() throws {
        let store = UserDefaultsHistoryStore(
            suiteName: "test.history.\(UUID().uuidString)",
            capacity: 3
        )
        let urlA = try url("https://example.com/a")

        try store.addEntry(BrowserHistoryEntry(url: urlA, title: "A"))
        try store.addEntry(BrowserHistoryEntry(url: urlA, title: "A again"))

        let entries = store.loadEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.title == "A again")

        try store.addEntry(BrowserHistoryEntry(url: try url("https://example.com/b"), title: "B"))
        try store.addEntry(BrowserHistoryEntry(url: try url("https://example.com/c"), title: "C"))
        try store.addEntry(BrowserHistoryEntry(url: try url("https://example.com/d"), title: "D"))

        #expect(store.loadEntries().count == 3)

        try store.clear()
        #expect(store.loadEntries().isEmpty)
    }

    @Test func bookmarkStoreAddRemove() throws {
        let store = UserDefaultsBookmarkStore(suiteName: "test.bookmarks.\(UUID().uuidString)")
        let bookmark = Bookmark(url: try url("https://example.com"), title: "Example")

        try store.addBookmark(bookmark)
        #expect(store.loadBookmarks().count == 1)

        try store.removeBookmark(id: bookmark.id)
        #expect(store.loadBookmarks().isEmpty)
    }

    @Test func profileStoreRoundTrip() throws {
        let store = UserDefaultsProfileStore(suiteName: "test.profiles.\(UUID().uuidString)")
        let profile = RemoteServerProfile(
            name: "NAS",
            rootURL: try url("https://nas.local/dav/"),
            username: "user"
        )

        try store.saveProfile(profile)
        let loaded = store.loadProfiles()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "NAS")

        try store.deleteProfile(id: profile.id)
        #expect(store.loadProfiles().isEmpty)
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}

import Foundation

/// 基于 UserDefaults 的收藏存储（JSON 编码）。
public struct UserDefaultsBookmarkStore: BookmarkStoring {
    private static let key = "browser.bookmarks.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadBookmarks() -> [Bookmark] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    public func addBookmark(_ bookmark: Bookmark) throws {
        var bookmarks = loadBookmarks()
        bookmarks.removeAll { $0.url == bookmark.url }
        bookmarks.insert(bookmark, at: 0)
        let data = try JSONEncoder().encode(bookmarks)
        defaults.set(data, forKey: Self.key)
    }

    public func removeBookmark(id: UUID) throws {
        var bookmarks = loadBookmarks()
        bookmarks.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(bookmarks)
        defaults.set(data, forKey: Self.key)
    }
}

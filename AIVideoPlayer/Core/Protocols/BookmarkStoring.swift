import Foundation

/// 收藏存取。
public protocol BookmarkStoring: Sendable {
    func loadBookmarks() -> [Bookmark]
    func addBookmark(_ bookmark: Bookmark) throws
    func removeBookmark(id: UUID) throws
}

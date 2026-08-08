import Foundation

/// 浏览器收藏条目。
public struct Bookmark: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let createdAt: Date

    public init(id: UUID = UUID(), url: URL, title: String, createdAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.createdAt = createdAt
    }
}

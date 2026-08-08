import Foundation

/// 浏览器历史条目。
public struct BrowserHistoryEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let visitedAt: Date

    public init(id: UUID = UUID(), url: URL, title: String, visitedAt: Date = .now) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }
}

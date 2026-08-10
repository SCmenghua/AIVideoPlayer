import Foundation

/// 主页「标签页」条目：用户在首页手动添加的快捷入口（非收藏，收藏保持原状）。
public struct HomeTab: Identifiable, Hashable, Sendable, Codable {
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

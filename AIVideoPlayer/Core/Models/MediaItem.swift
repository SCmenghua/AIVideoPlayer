import Foundation

/// 可播放的媒体资源，由 MediaExtractor 产出。
/// 远程文件条目在进入播放流程前会映射为 MediaItem。
public struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let title: String
    public let url: URL
    public let kind: Kind
    public let source: Source

    public enum Kind: String, Codable, Sendable {
        case video
        case audio
    }

    public enum Source: String, Codable, Sendable {
        case remote   // WebDAV / SMB / FTP
        case web      // 从网页中提取
        case local    // 设备本地文件（后续 Phase）
    }

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        kind: Kind,
        source: Source
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.source = source
    }
}

import Foundation

/// 媒体来源类型：网络（当前仅 WebDAV）/ 相册。
///
/// 后期扩展提示：`.files`（文件 App 导入）在 Phase 7.13 因导入不稳定已下线，
/// 但**保留该枚举值**——一是兼容旧数据解码（已保存的 .files 来源不会导致
/// 整个来源列表解析失败），二是为后续恢复文件导入能力预留扩展点。
/// 恢复时参考 MediaSourcesViewModel 中「文件来源」预留注释与
/// MediaSourcesSection 的占位入口（FilesSourceUnavailableView）。
public enum MediaSourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case webDAV
    case photoLibrary
    /// 已下线（Phase 7.13）：文件 App 导入功能移除，保留枚举值。
    case files

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .webDAV: "网络（WebDAV）"
        case .photoLibrary: "相册"
        case .files: "文件"
        }
    }

    public var systemImage: String {
        switch self {
        case .webDAV: "server.rack"
        case .photoLibrary: "photo.on.rectangle.angled"
        case .files: "folder"
        }
    }
}

/// 主页媒体来源条目。WebDAV 来源关联服务器配置 ID；相册来源无附加配置。
public struct MediaSource: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var kind: MediaSourceKind
    public var webDAVProfileID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: MediaSourceKind,
        webDAVProfileID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.webDAVProfileID = webDAVProfileID
        self.createdAt = createdAt
    }
}

import Foundation

/// 媒体来源类型：网络（当前仅 WebDAV）/ 相册 / 文件。
public enum MediaSourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case webDAV
    case photoLibrary
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

/// 主页媒体来源条目。WebDAV 来源关联服务器配置 ID；相册/文件来源无附加配置。
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

/// 文件来源中手动选取的视频文件（安全作用域书签，跨启动可用）。
public struct PickedVideoFile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let bookmarkData: Data
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, bookmarkData: Data, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
    }
}

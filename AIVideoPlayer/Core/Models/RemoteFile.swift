import Foundation

/// 远程目录列表中的一条（WebDAV / SMB / FTP）。
/// Phase 2 用真实目录模型替换 Mock。
public struct RemoteFile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let kind: Kind
    public let connection: Connection
    public let size: Int64?
    public let modifiedAt: Date?

    public enum Kind: String, Codable, Sendable {
        case folder
        case video
        case audio
        case image
        case document
        case other
    }

    public enum Connection: String, Codable, Sendable {
        case webdav
        case smb
        case ftp
        case local
    }

    public var isPlayable: Bool {
        kind == .video || kind == .audio
    }

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        kind: Kind,
        connection: Connection,
        size: Int64? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.kind = kind
        self.connection = connection
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

extension RemoteFile.Kind {
    /// 根据目录/文件类型与扩展名推断条目类型（Phase 2 WebDAV 使用）。
    static func infer(isCollection: Bool, url: URL) -> RemoteFile.Kind {
        if isCollection { return .folder }
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "m3u8", "m3u":
            return .video
        case "mp3", "m4a", "wav", "aac", "flac":
            return .audio
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .image
        case "pdf", "doc", "docx", "txt", "md", "epub":
            return .document
        default:
            return .other
        }
    }
}

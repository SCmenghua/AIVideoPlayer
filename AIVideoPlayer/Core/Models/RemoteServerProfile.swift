import Foundation

/// 远程服务器连接配置。username 非敏感信息可持久化；password 只存 Keychain。
public struct RemoteServerProfile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var rootURL: URL
    public var username: String

    public init(id: UUID = UUID(), name: String, rootURL: URL, username: String) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.username = username
    }
}

import Foundation

/// 远程服务器凭据。仅用于连接过程与内存中的会话；持久化只走 Keychain。
public struct RemoteCredentials: Hashable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

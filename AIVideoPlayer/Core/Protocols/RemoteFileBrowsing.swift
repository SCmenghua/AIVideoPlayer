import Foundation

/// 远程文件浏览能力。Phase 2 交付 WebDAV 实现；SMB / FTP 由后续阶段补充。
/// 使用前先 connect 建立会话，再 listDirectory 浏览目录，最后 disconnect 释放。
/// 取消调用方 Task 即取消当前操作。
public protocol RemoteFileBrowsing: Sendable {
    /// 使用给定凭据连接服务器；失败抛出错误（如凭据无效）。
    func connect(to profile: RemoteServerProfile, credentials: RemoteCredentials) async throws
    /// 列出目录内容（url 为目录 URL）。
    func listDirectory(at url: URL) async throws -> [RemoteFile]
    /// 结束会话并清除内存中的凭据。
    func disconnect() async
}

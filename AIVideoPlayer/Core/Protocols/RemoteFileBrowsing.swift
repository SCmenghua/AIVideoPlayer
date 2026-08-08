import Foundation

/// 远程文件浏览能力（WebDAV / SMB / FTP 目录列表）。
/// Phase 1 使用 MockRemoteFileBrowser，Phase 2 由真实实现替换。
/// 取消调用方 Task 即取消浏览。
public protocol RemoteFileBrowsing: Sendable {
    func listRemoteFiles() async throws -> [RemoteFile]
}

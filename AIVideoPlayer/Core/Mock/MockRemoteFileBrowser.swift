import Foundation

/// Phase 1 Mock 远程文件浏览器：模拟网络延迟后返回占位列表。
/// 遵循取消语义：调用方 Task 被取消时立即停止。
public struct MockRemoteFileBrowser: RemoteFileBrowsing {
    public init() {}

    public func listRemoteFiles() async throws -> [RemoteFile] {
        try await Task.sleep(for: .seconds(0.6))
        try Task.checkCancellation()
        return MockRemoteFiles.contents
    }
}

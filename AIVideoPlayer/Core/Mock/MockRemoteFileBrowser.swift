import Foundation

/// Phase 2 Mock 远程文件浏览器：模拟连接与目录浏览。
/// 遵循取消语义：调用方 Task 被取消时立即停止。
public struct MockRemoteFileBrowser: RemoteFileBrowsing {
    private let files: [RemoteFile]

    public init(files: [RemoteFile] = MockRemoteFiles.contents) {
        self.files = files
    }

    public func connect(to profile: RemoteServerProfile, credentials: RemoteCredentials) async throws {
        try await Task.sleep(for: .seconds(0.3))
        try Task.checkCancellation()
    }

    public func listDirectory(at url: URL) async throws -> [RemoteFile] {
        try await Task.sleep(for: .seconds(0.6))
        try Task.checkCancellation()
        return files
    }

    public func disconnect() async {
    }
}

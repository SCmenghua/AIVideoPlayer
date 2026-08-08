import Foundation
import Observation

/// Phase 1 Mock 浏览器状态。Phase 2 用真实的
/// WebDAV / SMB / FTP 目录浏览替换 refresh。所有 Task 可取消。
@MainActor
@Observable
final class BrowserViewModel {
    private(set) var remoteFiles: LoadState<[RemoteFile]> = .loading

    private let browser: any RemoteFileBrowsing
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?

    init(browser: any RemoteFileBrowsing = MockRemoteFileBrowser()) {
        self.browser = browser
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        remoteFiles = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await self.browser.listRemoteFiles()
                try Task.checkCancellation()
                guard generation == self.refreshGeneration else { return }
                self.remoteFiles = files.isEmpty ? .empty : .ready(files)
            } catch {
                guard generation == self.refreshGeneration else { return }
                self.remoteFiles = Task.isCancelled ? .cancelled : .error(error.localizedDescription)
            }
        }
        refreshTask = task
        await task.value
    }
}

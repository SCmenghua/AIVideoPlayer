import Foundation
import Observation

/// 远程文件浏览状态：连接管理、目录导航与目录内容加载。
@MainActor
@Observable
final class RemoteFilesViewModel {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting(RemoteServerProfile)
        case connected(RemoteServerProfile)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var directoryStack: [RemoteFile] = []
    private(set) var currentDirectory: URL?
    private(set) var files: LoadState<[RemoteFile]> = .loading
    private(set) var profiles: [RemoteServerProfile] = []
    private(set) var lastError: String?

    private let browser: any RemoteFileBrowsing
    private let credentialStore: any CredentialStoring
    private let profileStore: any RemoteServerProfileStoring

    private var generation = 0
    private var loadTask: Task<Void, Never>?

    init(
        browser: any RemoteFileBrowsing = WebDAVFileBrowser(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        profileStore: any RemoteServerProfileStoring = UserDefaultsProfileStore()
    ) {
        self.browser = browser
        self.credentialStore = credentialStore
        self.profileStore = profileStore
        self.profiles = profileStore.loadProfiles()
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    private var connectedProfile: RemoteServerProfile? {
        switch connectionState {
        case .connected(let profile):
            return profile
        case .disconnected, .connecting:
            return nil
        }
    }

    // MARK: - 连接

    /// 新增或更新服务器并连接。
    func connect(name: String, rootURL: URL, username: String, password: String) async {
        let profile = makeProfile(name: name, rootURL: rootURL, username: username)
        connectionState = .connecting(profile)
        lastError = nil

        do {
            try profileStore.saveProfile(profile)
            try credentialStore.savePassword(password, for: profile.id)
            try await browser.connect(to: profile, credentials: RemoteCredentials(username: username, password: password))
            profiles = profileStore.loadProfiles()
            connectionState = .connected(profile)
            await refreshRoot(profile: profile)
        } catch {
            lastError = error.localizedDescription
            connectionState = .disconnected
        }
    }

    /// 用已保存的凭据重新连接。
    func reconnect(profile: RemoteServerProfile) async {
        guard let password = try? credentialStore.loadPassword(for: profile.id) else {
            lastError = "未找到该服务器的已保存密码，请重新添加。"
            return
        }
        await connect(name: profile.name, rootURL: profile.rootURL, username: profile.username, password: password)
    }

    func disconnect() async {
        loadTask?.cancel()
        await browser.disconnect()
        connectionState = .disconnected
        directoryStack.removeAll()
        currentDirectory = nil
        files = .loading
    }

    func deleteProfile(_ profile: RemoteServerProfile) async {
        try? credentialStore.deletePassword(for: profile.id)
        try? profileStore.deleteProfile(id: profile.id)
        profiles = profileStore.loadProfiles()
    }

    private func makeProfile(name: String, rootURL: URL, username: String) -> RemoteServerProfile {
        if let existing = profiles.first(where: { $0.rootURL == rootURL }) {
            return RemoteServerProfile(id: existing.id, name: name, rootURL: rootURL, username: username)
        }
        return RemoteServerProfile(name: name, rootURL: rootURL, username: username)
    }

    // MARK: - 浏览

    /// 打开条目：文件夹进入目录；媒体文件 Phase 3 接入播放器（当前不处理）。
    func open(_ file: RemoteFile) async {
        if file.kind == .folder {
            await listDirectory(at: file.url, pushing: file)
        }
    }

    func refresh() async {
        guard let currentDirectory else { return }
        await listDirectory(at: currentDirectory, pushing: nil)
    }

    func goBack() async {
        guard !directoryStack.isEmpty else { return }
        directoryStack.removeLast()
        let target = directoryStack.last?.url ?? connectedProfile?.rootURL
        if let target {
            await listDirectory(at: target, pushing: nil)
        }
    }

    func goToRoot() async {
        guard let profile = connectedProfile else { return }
        directoryStack.removeAll()
        await listDirectory(at: profile.rootURL, pushing: nil)
    }

    /// 跳转到面包屑中的某个层级：截断目录栈并加载该目录。
    func jumpTo(folder: RemoteFile) async {
        guard let index = directoryStack.firstIndex(where: { $0.id == folder.id }) else { return }
        directoryStack.removeSubrange((index + 1)...)
        await listDirectory(at: folder.url, pushing: nil)
    }

    private func refreshRoot(profile: RemoteServerProfile) async {
        directoryStack.removeAll()
        await listDirectory(at: profile.rootURL, pushing: nil)
    }

    private func listDirectory(at url: URL, pushing pushed: RemoteFile?) async {
        generation += 1
        let currentGeneration = generation
        loadTask?.cancel()
        files = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.browser.listDirectory(at: url)
                try Task.checkCancellation()
                guard currentGeneration == self.generation else { return }
                if let pushed {
                    self.directoryStack.append(pushed)
                }
                self.currentDirectory = url
                self.files = items.isEmpty ? .empty : .ready(items)
            } catch {
                guard currentGeneration == self.generation else { return }
                self.files = Task.isCancelled ? .cancelled : .error(error.localizedDescription)
            }
        }
        loadTask = task
        await task.value
    }
}

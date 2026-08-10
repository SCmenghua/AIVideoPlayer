import Foundation
import Observation

/// 主页「媒体来源」管理：网络（WebDAV）/ 相册 / 文件三类来源的增删与展示。
@MainActor
@Observable
final class MediaSourcesViewModel {
    private(set) var sources: [MediaSource] = []
    private(set) var pickedFiles: [PickedVideoFile] = []
    private(set) var lastError: String?

    private let sourceStore: any MediaSourceStoring
    private let profileStore: any RemoteServerProfileStoring
    private let credentialStore: any CredentialStoring
    private let pickedFileStore: any PickedFileStoring
    private let browser: any RemoteFileBrowsing

    init(
        sourceStore: any MediaSourceStoring = UserDefaultsMediaSourceStore(),
        profileStore: any RemoteServerProfileStoring = UserDefaultsProfileStore(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        pickedFileStore: any PickedFileStoring = UserDefaultsPickedFileStore(),
        browser: any RemoteFileBrowsing = WebDAVFileBrowser()
    ) {
        self.sourceStore = sourceStore
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        self.pickedFileStore = pickedFileStore
        self.browser = browser
        self.sources = sourceStore.loadSources()
        self.pickedFiles = pickedFileStore.loadFiles()
    }

    // MARK: - 来源增删

    /// 添加 WebDAV 来源：保存服务器配置与密码，验证连接成功后登记来源。
    /// 返回是否成功；失败时 `lastError` 给出原因。
    func addWebDAVSource(name: String, rootURL: URL, username: String, password: String) async -> Bool {
        lastError = nil
        let profile = makeProfile(name: name, rootURL: rootURL, username: username)
        do {
            try profileStore.saveProfile(profile)
            try credentialStore.savePassword(password, for: profile.id)
            try await browser.connect(
                to: profile,
                credentials: RemoteCredentials(username: username, password: password)
            )
            await browser.disconnect()
        } catch {
            lastError = error.localizedDescription
            return false
        }

        let resolvedName = Self.resolveName(name, fallback: rootURL.host ?? rootURL.absoluteString)
        try? sourceStore.addSource(
            MediaSource(name: resolvedName, kind: .webDAV, webDAVProfileID: profile.id)
        )
        sources = sourceStore.loadSources()
        return true
    }

    func addPhotoLibrarySource(name: String = "") {
        addSource(kind: .photoLibrary, name: name, fallback: "相册")
    }

    func addFilesSource(name: String = "") {
        addSource(kind: .files, name: name, fallback: "文件")
    }

    func removeSource(_ source: MediaSource) {
        if let profileID = source.webDAVProfileID {
            try? credentialStore.deletePassword(for: profileID)
            try? profileStore.deleteProfile(id: profileID)
        }
        try? sourceStore.removeSource(id: source.id)
        sources = sourceStore.loadSources()
    }

    /// 解析 WebDAV 来源关联的服务器配置。
    func profile(for source: MediaSource) -> RemoteServerProfile? {
        guard let profileID = source.webDAVProfileID else { return nil }
        return profileStore.loadProfiles().first { $0.id == profileID }
    }

    private func addSource(kind: MediaSourceKind, name: String, fallback: String) {
        let resolvedName = Self.resolveName(name, fallback: fallback)
        try? sourceStore.addSource(MediaSource(name: resolvedName, kind: kind))
        sources = sourceStore.loadSources()
    }

    private func makeProfile(name: String, rootURL: URL, username: String) -> RemoteServerProfile {
        let existing = profileStore.loadProfiles().first { $0.rootURL == rootURL }
        if let existing {
            return RemoteServerProfile(id: existing.id, name: name, rootURL: rootURL, username: username)
        }
        return RemoteServerProfile(name: name, rootURL: rootURL, username: username)
    }

    private static func resolveName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: - 文件来源（Files App 安全作用域书签）

    /// 把文件选择器返回的 URL 转为安全作用域书签并持久化。
    func addPickedFiles(urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            // iOS 不支持 .withSecurityScope（仅 macOS）；普通书签即可持久化文件地址。
            guard let bookmark = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { continue }
            try? pickedFileStore.addFile(
                PickedVideoFile(name: url.lastPathComponent, bookmarkData: bookmark)
            )
        }
        pickedFiles = pickedFileStore.loadFiles()
    }

    func removePickedFile(_ file: PickedVideoFile) {
        try? pickedFileStore.removeFile(id: file.id)
        pickedFiles = pickedFileStore.loadFiles()
    }

    /// 解析书签为可播放 URL（返回前已开始安全作用域访问）。
    func resolvePickedFileURL(_ file: PickedVideoFile) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: file.bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}

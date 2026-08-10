import Foundation
import Observation

/// 主页「媒体来源」管理：网络（WebDAV）/ 相册两类来源的增删与展示。
///
/// 后期扩展提示：文件来源（MediaSourceKind.files）已在 Phase 7.13 下线，
/// 相关导入代码（复制到沙盒 / 书签持久化）已移除；恢复时在 `addFilesSource`
/// 占位处重新接入文件导入实现，并在 MediaSourcesSection 中替换
/// FilesSourceUnavailableView 占位视图。
@MainActor
@Observable
final class MediaSourcesViewModel {
    private(set) var sources: [MediaSource] = []
    private(set) var lastError: String?

    private let sourceStore: any MediaSourceStoring
    private let profileStore: any RemoteServerProfileStoring
    private let credentialStore: any CredentialStoring
    private let browser: any RemoteFileBrowsing

    init(
        sourceStore: any MediaSourceStoring = UserDefaultsMediaSourceStore(),
        profileStore: any RemoteServerProfileStoring = UserDefaultsProfileStore(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        browser: any RemoteFileBrowsing = WebDAVFileBrowser()
    ) {
        self.sourceStore = sourceStore
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        self.browser = browser
        self.sources = sourceStore.loadSources()
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

    /// 文件来源（Phase 7.13 下线）：占位方法，后续恢复文件导入时在此实现。
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

    // MARK: - 文件来源（Phase 7.13 下线，预留扩展点）
    //
    // 原「从文件 App 导入视频」实现（复制到 Documents/MediaFiles + 本地 URL
    // 持久化）因导入稳定性问题已在 Phase 7.13 移除。恢复时建议：
    // 1. 在 PickedVideoFile 模型恢复（或重新设计文件记录）；
    // 2. 在下方新增 `addPickedFiles(urls:)` / `removePickedFile(_:)`；
    // 3. 在 MediaSourcesSection 中把 FilesSourceUnavailableView 替换为
    //    FilesMediaSourceView。
}

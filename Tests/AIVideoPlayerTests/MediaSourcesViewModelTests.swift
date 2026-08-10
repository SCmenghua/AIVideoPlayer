import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct MediaSourcesViewModelTests {

    @Test func addWebDAVSourceCreatesSourceAndProfile() async throws {
        let sourceStore = MockMediaSourceStore()
        let viewModel = MediaSourcesViewModel(
            sourceStore: sourceStore,
            profileStore: UserDefaultsProfileStore(suiteName: "test.ms.profiles.\(UUID().uuidString)"),
            credentialStore: InMemoryCredentialStore(),
            browser: MockRemoteFileBrowser()
        )
        let rootURL = try #require(URL(string: "https://nas.example.local/dav/"))

        let ok = await viewModel.addWebDAVSource(name: "NAS", rootURL: rootURL, username: "u", password: "p")

        #expect(ok)
        #expect(viewModel.sources.count == 1)
        #expect(viewModel.sources.first?.kind == .webDAV)
        #expect(viewModel.sources.first?.webDAVProfileID != nil)
        #expect(sourceStore.loadSources().count == 1)
    }

    @Test func addWebDAVSourceFailsOnBadServer() async throws {
        let viewModel = MediaSourcesViewModel(
            sourceStore: MockMediaSourceStore(),
            profileStore: UserDefaultsProfileStore(suiteName: "test.ms.profiles.\(UUID().uuidString)"),
            credentialStore: InMemoryCredentialStore(),
            browser: FailingRemoteFileBrowser()
        )
        let rootURL = try #require(URL(string: "https://nas.example.local/dav/"))

        let ok = await viewModel.addWebDAVSource(name: "NAS", rootURL: rootURL, username: "u", password: "p")

        #expect(!ok)
        #expect(viewModel.sources.isEmpty)
        #expect(viewModel.lastError != nil)
    }

    @Test func photoAndFilesSourcesAddAndRemove() {
        let sourceStore = MockMediaSourceStore()
        let viewModel = MediaSourcesViewModel(
            sourceStore: sourceStore,
            profileStore: UserDefaultsProfileStore(suiteName: "test.ms.profiles.\(UUID().uuidString)"),
            credentialStore: InMemoryCredentialStore()
        )

        viewModel.addPhotoLibrarySource()
        viewModel.addFilesSource(name: "我的视频")

        #expect(viewModel.sources.count == 2)
        #expect(viewModel.sources.first?.kind == .files)
        #expect(viewModel.sources.first?.name == "我的视频")

        viewModel.removeSource(viewModel.sources.first!)
        #expect(viewModel.sources.count == 1)
        #expect(sourceStore.loadSources().count == 1)
    }

    @Test func removeWebDAVSourceDeletesProfile() async throws {
        let profileStore = UserDefaultsProfileStore(suiteName: "test.ms.profiles.\(UUID().uuidString)")
        let viewModel = MediaSourcesViewModel(
            sourceStore: MockMediaSourceStore(),
            profileStore: profileStore,
            credentialStore: InMemoryCredentialStore(),
            browser: MockRemoteFileBrowser()
        )
        let rootURL = try #require(URL(string: "https://nas.example.local/dav/"))

        await viewModel.addWebDAVSource(name: "NAS", rootURL: rootURL, username: "u", password: "p")
        #expect(profileStore.loadProfiles().count == 1)

        viewModel.removeSource(viewModel.sources.first!)

        #expect(viewModel.sources.isEmpty)
        #expect(profileStore.loadProfiles().isEmpty)
    }

}

private final class MockMediaSourceStore: MediaSourceStoring, @unchecked Sendable {
    private var sources: [MediaSource] = []

    func loadSources() -> [MediaSource] {
        sources
    }

    func addSource(_ source: MediaSource) throws {
        sources.removeAll { $0.id == source.id }
        sources.insert(source, at: 0)
    }

    func removeSource(id: UUID) throws {
        sources.removeAll { $0.id == id }
    }
}

private struct FailingRemoteFileBrowser: RemoteFileBrowsing {
    func connect(to profile: RemoteServerProfile, credentials: RemoteCredentials) async throws {
        throw TestConnectionError()
    }

    func listDirectory(at url: URL) async throws -> [RemoteFile] {
        []
    }

    func disconnect() async {}
}

private struct TestConnectionError: LocalizedError {
    var errorDescription: String? { "连接失败" }
}

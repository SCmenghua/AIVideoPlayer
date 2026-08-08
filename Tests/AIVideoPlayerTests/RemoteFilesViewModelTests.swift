import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct RemoteFilesViewModelTests {

    @Test func connectListsRoot() async throws {
        let viewModel = RemoteFilesViewModel(
            browser: MockRemoteFileBrowser(),
            credentialStore: InMemoryCredentialStore(),
            profileStore: UserDefaultsProfileStore(suiteName: "test.vm.profiles.\(UUID().uuidString)")
        )
        let rootURL = try #require(URL(string: "https://nas.example.local/dav/"))

        await viewModel.connect(name: "NAS", rootURL: rootURL, username: "u", password: "p")

        #expect(viewModel.isConnected)
        #expect(viewModel.files == .ready(MockRemoteFiles.contents))
    }

    @Test func disconnectClearsState() async throws {
        let viewModel = RemoteFilesViewModel(
            browser: MockRemoteFileBrowser(),
            credentialStore: InMemoryCredentialStore(),
            profileStore: UserDefaultsProfileStore(suiteName: "test.vm.profiles.\(UUID().uuidString)")
        )
        let rootURL = try #require(URL(string: "https://nas.example.local/dav/"))

        await viewModel.connect(name: "NAS", rootURL: rootURL, username: "u", password: "p")
        await viewModel.disconnect()

        #expect(!viewModel.isConnected)
        #expect(viewModel.directoryStack.isEmpty)
    }

    @Test func reconnectUsesSavedPassword() async throws {
        let credentialStore = InMemoryCredentialStore()
        let viewModel = RemoteFilesViewModel(
            browser: MockRemoteFileBrowser(),
            credentialStore: credentialStore,
            profileStore: UserDefaultsProfileStore(suiteName: "test.vm.profiles.\(UUID().uuidString)")
        )
        let rootURL = try #require(URL(string: "https://nas.example.local/dav/"))

        await viewModel.connect(name: "NAS", rootURL: rootURL, username: "u", password: "p")
        await viewModel.disconnect()

        guard let profile = viewModel.profiles.first else {
            Issue.record("连接后应保存 profile")
            return
        }

        await viewModel.reconnect(profile: profile)
        #expect(viewModel.isConnected)
    }
}

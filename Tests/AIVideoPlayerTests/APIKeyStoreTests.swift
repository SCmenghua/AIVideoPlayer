import Foundation
import Testing
@testable import AIVideoPlayer

struct APIKeyStoreTests {

    @Test(
        .disabled("Keychain 写入需要 App 签名 entitlement（errSecMissingEntitlement -34018），CI 模拟器不可用；与 KeychainCredentialStore 一致不在 CI 直测")
    )
    func keychainRoundTrip() throws {
        let store = KeychainAPIKeyStore()
        try store.deleteAPIKey()

        try store.saveAPIKey("sk-test-123")
        #expect(try store.loadAPIKey() == "sk-test-123")

        try store.saveAPIKey("sk-test-456")
        #expect(try store.loadAPIKey() == "sk-test-456")

        try store.deleteAPIKey()
        #expect(try store.loadAPIKey() == nil)
    }

    @Test(
        .disabled("Keychain 写入需要 App 签名 entitlement（errSecMissingEntitlement -34018），CI 模拟器不可用")
    )
    func deletingMissingKeyDoesNotThrow() throws {
        let store = KeychainAPIKeyStore()
        try store.deleteAPIKey()
        try store.deleteAPIKey()
        #expect(try store.loadAPIKey() == nil)
    }
}

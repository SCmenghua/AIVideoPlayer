import Foundation
import Testing
@testable import AIVideoPlayer

struct APIKeyStoreTests {

    @Test func keychainRoundTrip() throws {
        let store = KeychainAPIKeyStore()
        try store.deleteAPIKey()

        try store.saveAPIKey("sk-test-123")
        #expect(try store.loadAPIKey() == "sk-test-123")

        try store.saveAPIKey("sk-test-456")
        #expect(try store.loadAPIKey() == "sk-test-456")

        try store.deleteAPIKey()
        #expect(try store.loadAPIKey() == nil)
    }

    @Test func deletingMissingKeyDoesNotThrow() throws {
        let store = KeychainAPIKeyStore()
        try store.deleteAPIKey()
        try store.deleteAPIKey()
        #expect(try store.loadAPIKey() == nil)
    }
}

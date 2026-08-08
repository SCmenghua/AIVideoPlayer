import Foundation
import Testing
@testable import AIVideoPlayer

struct CredentialStoreTests {

    @Test func inMemoryCredentialStoreRoundTrip() throws {
        let store = InMemoryCredentialStore()
        let profileID = UUID()

        try store.savePassword("secret", for: profileID)
        let loaded = try store.loadPassword(for: profileID)
        #expect(loaded == "secret")

        try store.deletePassword(for: profileID)
        let afterDelete = try store.loadPassword(for: profileID)
        #expect(afterDelete == nil)
    }

    @Test func inMemoryCredentialStoreIsPerProfile() throws {
        let store = InMemoryCredentialStore()
        let first = UUID()
        let second = UUID()

        try store.savePassword("one", for: first)
        try store.savePassword("two", for: second)

        let firstValue = try store.loadPassword(for: first)
        let secondValue = try store.loadPassword(for: second)
        #expect(firstValue == "one")
        #expect(secondValue == "two")
    }
}

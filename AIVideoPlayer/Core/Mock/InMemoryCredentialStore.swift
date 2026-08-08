import Foundation

/// 内存凭据存储（预览与测试用；生产使用 KeychainCredentialStore）。
public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [UUID: String] = [:]

    public init() {}

    public func savePassword(_ password: String, for profileID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        passwords[profileID] = password
    }

    public func loadPassword(for profileID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return passwords[profileID]
    }

    public func deletePassword(for profileID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        passwords.removeValue(forKey: profileID)
    }
}

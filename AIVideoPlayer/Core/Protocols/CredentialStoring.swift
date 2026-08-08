import Foundation

/// 凭据存取。实现必须保证密码仅安全持久化（生产实现为 Keychain）。
public protocol CredentialStoring: Sendable {
    func savePassword(_ password: String, for profileID: UUID) throws
    func loadPassword(for profileID: UUID) throws -> String?
    func deletePassword(for profileID: UUID) throws
}

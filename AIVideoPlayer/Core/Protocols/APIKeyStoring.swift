import Foundation

/// 云端翻译 API Key 存取（生产实现 Keychain；红线：凭据只存本机 Keychain）。
public protocol APIKeyStoring: Sendable {
    func saveAPIKey(_ key: String) throws
    func loadAPIKey() throws -> String?
    func deleteAPIKey() throws
}

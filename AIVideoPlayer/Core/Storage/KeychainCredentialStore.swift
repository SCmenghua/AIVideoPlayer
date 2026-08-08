import Foundation
import Security

/// 基于 Keychain 的凭据存储（kSecClassGenericPassword）。
/// 无状态结构体；方法同步且线程安全（由 Keychain 服务保证）。
public struct KeychainCredentialStore: CredentialStoring {
    private let service = "com.aivideoplayer.server"

    public init() {}

    public func savePassword(_ password: String, for profileID: UUID) throws {
        let account = profileID.uuidString
        let data = Data(password.utf8)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // 先删除旧值再写入，避免 Keychain 重复条目。
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func loadPassword(for profileID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    public func deletePassword(for profileID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }
}

/// Keychain 操作错误。
public enum KeychainError: LocalizedError {
    case unhandled(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            "Keychain 操作失败（OSStatus \(status)）"
        }
    }
}

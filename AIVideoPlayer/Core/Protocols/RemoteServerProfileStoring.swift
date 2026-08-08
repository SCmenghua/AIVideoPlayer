import Foundation

/// 服务器配置存取（仅非敏感信息；密码走 CredentialStoring）。
public protocol RemoteServerProfileStoring: Sendable {
    func loadProfiles() -> [RemoteServerProfile]
    func saveProfile(_ profile: RemoteServerProfile) throws
    func deleteProfile(id: UUID) throws
}

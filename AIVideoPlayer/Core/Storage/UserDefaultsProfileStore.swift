import Foundation

/// 基于 UserDefaults 的服务器配置存储（非敏感信息）。
public struct UserDefaultsProfileStore: RemoteServerProfileStoring {
    private static let key = "remote.profiles.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadProfiles() -> [RemoteServerProfile] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([RemoteServerProfile].self, from: data)) ?? []
    }

    public func saveProfile(_ profile: RemoteServerProfile) throws {
        var profiles = loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        let data = try JSONEncoder().encode(profiles)
        defaults.set(data, forKey: Self.key)
    }

    public func deleteProfile(id: UUID) throws {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(profiles)
        defaults.set(data, forKey: Self.key)
    }
}

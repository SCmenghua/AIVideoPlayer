import Foundation

/// 基于 UserDefaults 的媒体来源存储（JSON 编码）。
public struct UserDefaultsMediaSourceStore: MediaSourceStoring {
    private static let key = "media.sources.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadSources() -> [MediaSource] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([MediaSource].self, from: data)) ?? []
    }

    public func addSource(_ source: MediaSource) throws {
        var sources = loadSources()
        sources.removeAll { $0.id == source.id }
        sources.insert(source, at: 0)
        let data = try JSONEncoder().encode(sources)
        defaults.set(data, forKey: Self.key)
    }

    public func removeSource(id: UUID) throws {
        var sources = loadSources()
        sources.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(sources)
        defaults.set(data, forKey: Self.key)
    }
}

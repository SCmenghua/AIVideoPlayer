import Foundation

/// 基于 UserDefaults 的历史存储（JSON 编码，按访问时间倒序，可配置容量上限）。
public struct UserDefaultsHistoryStore: BrowserHistoryStoring {
    private static let key = "browser.history.v1"
    private let suiteName: String?
    private let capacity: Int

    public init(suiteName: String? = nil, capacity: Int = 100) {
        self.suiteName = suiteName
        self.capacity = capacity
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadEntries() -> [BrowserHistoryEntry] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([BrowserHistoryEntry].self, from: data)) ?? []
    }

    public func addEntry(_ entry: BrowserHistoryEntry) throws {
        var entries = loadEntries()
        // 同一 URL 只保留最新一次访问。
        entries.removeAll { $0.url == entry.url }
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries = Array(entries.prefix(capacity))
        }
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: Self.key)
    }

    public func clear() throws {
        defaults.removeObject(forKey: Self.key)
    }
}

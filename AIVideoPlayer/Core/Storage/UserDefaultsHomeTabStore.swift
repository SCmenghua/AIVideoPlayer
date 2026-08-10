import Foundation

/// 基于 UserDefaults 的主页标签页存储（JSON 编码）。
public struct UserDefaultsHomeTabStore: HomeTabStoring {
    private static let key = "browser.homeTabs.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadTabs() -> [HomeTab] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([HomeTab].self, from: data)) ?? []
    }

    public func addTab(_ tab: HomeTab) throws {
        var tabs = loadTabs()
        tabs.removeAll { $0.url == tab.url }
        tabs.insert(tab, at: 0)
        let data = try JSONEncoder().encode(tabs)
        defaults.set(data, forKey: Self.key)
    }

    public func removeTab(id: UUID) throws {
        var tabs = loadTabs()
        tabs.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(tabs)
        defaults.set(data, forKey: Self.key)
    }
}

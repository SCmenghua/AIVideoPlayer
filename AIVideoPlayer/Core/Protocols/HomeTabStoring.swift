import Foundation

/// 主页标签页存取（与收藏/历史相互独立）。
public protocol HomeTabStoring: Sendable {
    func loadTabs() -> [HomeTab]
    func addTab(_ tab: HomeTab) throws
    func removeTab(id: UUID) throws
}

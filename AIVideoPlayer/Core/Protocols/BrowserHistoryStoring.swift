import Foundation

/// 浏览历史存取。协议隔离持久化实现（Phase 2 使用 UserDefaults，后续可换 SwiftData）。
public protocol BrowserHistoryStoring: Sendable {
    func loadEntries() -> [BrowserHistoryEntry]
    func addEntry(_ entry: BrowserHistoryEntry) throws
    func clear() throws
}

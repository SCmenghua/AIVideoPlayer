import Foundation

/// 主页媒体来源存取。
public protocol MediaSourceStoring: Sendable {
    func loadSources() -> [MediaSource]
    func addSource(_ source: MediaSource) throws
    func removeSource(id: UUID) throws
}

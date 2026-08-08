import Foundation

/// 字幕时间线管理（Phase 6 用于播放器 Overlay）。
@MainActor
public protocol SubtitleEngine: AnyObject {
    var segments: [SubtitleSegment] { get }

    func append(_ segment: SubtitleSegment) async
    func update(_ segment: SubtitleSegment) async
    func removeAll() async
    func segment(at time: TimeInterval) -> SubtitleSegment?
}

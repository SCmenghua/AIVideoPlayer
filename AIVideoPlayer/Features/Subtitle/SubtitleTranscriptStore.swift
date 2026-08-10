import Foundation
import Observation

/// 共享字幕记录存储（Phase 8.5 重构）：
/// - 字幕管线的每一条识别 / 翻译结果（原文 + 译文）写入这里，作为唯一数据源；
/// - 播放器 Overlay 按播放光标实时查询，设置页「字幕记录」卡片展示最近条目；
/// - 有界存储（保留最近 N 条），final 到达时收敛相交的 partial，
///   避免逐词残留与无界增长。
@MainActor
@Observable
public final class SubtitleTranscriptStore {
    /// 最多保留的字幕条数（设置页调试查看窗口）。
    public static let maxStoredSegments = 200

    public private(set) var segments: [SubtitleSegment] = []

    public init() {}

    /// 追加一条字幕（识别 / 翻译后由管线写入，调用方已过 MainActor）。
    public func append(_ segment: SubtitleSegment) {
        if !segment.isPartial {
            // final 到达后，清理与它相交的旧 partial，避免逐词残留。
            segments.removeAll { existing in
                existing.isPartial && Self.overlaps(existing, segment)
            }
        }
        insertSorted(segment)
        trimIfNeeded()
    }

    /// 当前时刻应显示的字幕：同一时刻既有 partial 又有 final 时优先 final；
    /// 多个 partial 重叠时取最近写入的一条（代表最新识别进度）。
    public func segment(at time: TimeInterval) -> SubtitleSegment? {
        let candidates = segments.filter {
            $0.startTime <= time && time < Self.displayEndTime(of: $0)
        }
        return candidates.last(where: { !$0.isPartial }) ?? candidates.last
    }

    /// 清空全部记录（播放器换片 / 管线关闭 / 设置页手动清空）。
    public func clear() {
        segments.removeAll(keepingCapacity: true)
    }

    // MARK: - Private

    private func insertSorted(_ segment: SubtitleSegment) {
        let index = segments.firstIndex { $0.startTime > segment.startTime } ?? segments.endIndex
        segments.insert(segment, at: index)
    }

    private func trimIfNeeded() {
        guard segments.count > Self.maxStoredSegments else { return }
        segments.removeFirst(segments.count - Self.maxStoredSegments)
    }

    private static func overlaps(_ lhs: SubtitleSegment, _ rhs: SubtitleSegment) -> Bool {
        lhs.startTime < rhs.endTime && rhs.startTime < lhs.endTime
    }

    /// 显示用结束时间：零 / 负时长片段按最小可显示窗口兜底，
    /// 避免时间戳异常的 final 永远无法命中播放光标（显示链路丢字幕）。
    private static func displayEndTime(of segment: SubtitleSegment) -> TimeInterval {
        segment.endTime > segment.startTime
            ? segment.endTime
            : segment.startTime + SubtitleSegment.minimumDisplayDuration
    }
}

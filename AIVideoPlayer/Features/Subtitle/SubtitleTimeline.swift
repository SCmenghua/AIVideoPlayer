import Foundation

/// SubtitleEngine 的真实实现（Phase 6）：
/// 维护按时间排序的字幕时间线，供播放器 Overlay 按播放光标取当前句子。
/// 规则：
/// - `segment(at:)` 返回覆盖该时刻的整句字幕；同一时刻既有 partial 又有 final 时优先 final；
/// - append final 时清理与被其时间区间相交的旧 partial（原始实时路径 partial → final 收敛）；
/// - 时间线按 startTime 排序；超过上限时丢弃最旧条目，避免无界增长。
@MainActor
public final class SubtitleTimeline: SubtitleEngine {
    public private(set) var segments: [SubtitleSegment] = []

    private static let maxSegmentCount = 500

    public init() {}

    public func append(_ segment: SubtitleSegment) async {
        if !segment.isPartial {
            // final 到达后，清理与它相交的旧 partial，避免逐词残留。
            segments.removeAll { existing in
                existing.isPartial
                    && existing.startTime < segment.endTime
                    && segment.startTime < existing.endTime
            }
        }
        insertSorted(segment)
        trimIfNeeded()
    }

    public func update(_ segment: SubtitleSegment) async {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else {
            await append(segment)
            return
        }
        segments[index] = segment
        // 时间区间可能变化，重新排序保持时间线有序。
        segments.sort { $0.startTime < $1.startTime }
    }

    public func removeAll() async {
        segments.removeAll(keepingCapacity: true)
    }

    public func segment(at time: TimeInterval) -> SubtitleSegment? {
        let candidates = segments.filter {
            $0.startTime <= time && time < $0.endTime
        }
        return candidates.first(where: { !$0.isPartial }) ?? candidates.first
    }

    // MARK: - Private

    private func insertSorted(_ segment: SubtitleSegment) {
        let index = segments.firstIndex { $0.startTime > segment.startTime } ?? segments.endIndex
        segments.insert(segment, at: index)
    }

    private func trimIfNeeded() {
        guard segments.count > Self.maxSegmentCount else { return }
        segments.removeFirst(segments.count - Self.maxSegmentCount)
    }
}

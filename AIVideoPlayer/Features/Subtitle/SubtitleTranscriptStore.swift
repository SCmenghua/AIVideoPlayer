import Foundation
import Observation

/// 共享字幕记录存储（Phase 8.12 性能优化）：
/// - 字幕管线的每一条识别 / 翻译结果（原文 + 译文）写入这里，作为唯一数据源；
/// - 播放器 Overlay 按播放光标实时查询，设置页「字幕记录」卡片展示最近条目；
/// - 有界存储（保留最近 N 条），final 到达时收敛相交的 partial，
///   避免逐词残留与无界增长。
/// - **批量更新 + 节流**：避免每次 append 都触发 @Observable 的 UI 刷新，
///   防止高频识别结果卡死主线程。
@MainActor
@Observable
public final class SubtitleTranscriptStore {
    /// 最多保留的字幕条数（设置页调试查看窗口）。
    public static let maxStoredSegments = 200

    public private(set) var segments: [SubtitleSegment] = []

    /// 最近 20 条字幕（优化卡片性能，Phase 8.17）。
    public var recentSegments: [SubtitleSegment] {
        Array(segments.suffix(20).reversed())
    }

    /// 待提交的缓冲区：累积多条字幕后批量写入 segments，减少 UI 刷新频率。
    private var pendingSegments: [SubtitleSegment] = []
    private var flushTask: Task<Void, Never>?
    private var lastFlushTime: ContinuousClock.Instant = .now

    /// UI 刷新节流间隔（毫秒）：最快每 150ms 刷新一次，避免高频卡顿。
    private static let flushInterval: Duration = .milliseconds(150)

    public init() {}

    /// 追加一条字幕（识别 / 翻译后由管线写入，调用方已过 MainActor）。
    /// 不立即触发 UI 刷新，而是累积到缓冲区，定期批量提交。
    public func append(_ segment: SubtitleSegment) {
        pendingSegments.append(segment)
        scheduleFlush()
    }

    /// 立即刷新所有待提交的字幕到 segments（触发 UI 更新）。
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        commitPendingSegments()
    }

    private func scheduleFlush() {
        // 已有定时任务在运行，不重复调度
        guard flushTask == nil else { return }

        let now = ContinuousClock.Instant.now
        let elapsed = lastFlushTime.duration(to: now)

        // 距离上次刷新不足节流间隔，延迟刷新
        if elapsed < Self.flushInterval {
            let delay = Self.flushInterval - elapsed
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        } else {
            // 距离上次刷新已超过节流间隔，立即刷新
            flush()
        }
    }

    private func commitPendingSegments() {
        guard !pendingSegments.isEmpty else { return }

        for segment in pendingSegments {
            if !segment.isPartial {
                // final 到达后，清理与它相交的旧 partial，避免逐词残留。
                segments.removeAll { existing in
                    existing.isPartial && Self.overlaps(existing, segment)
                }
            }
            insertSorted(segment)
        }

        pendingSegments.removeAll(keepingCapacity: true)
        trimIfNeeded()
        lastFlushTime = .now
    }

    /// 当前时刻应显示的字幕：同一时刻既有 partial 又有 final 时优先 final；
    /// 多个 partial 重叠时取最近写入的一条（代表最新识别进度）。
    /// 查询时会先将待提交的字幕合并到主存储，确保最新结果立即可见。
    public func segment(at time: TimeInterval) -> SubtitleSegment? {
        // 查询前先刷新缓冲区，确保最新字幕立即可见（不等待定时器）
        if !pendingSegments.isEmpty {
            flush()
        }

        let candidates = segments.filter {
            $0.startTime <= time && time < Self.displayEndTime(of: $0)
        }
        return candidates.last(where: { !$0.isPartial }) ?? candidates.last
    }

    /// 清空全部记录（播放器换片 / 管线关闭 / 设置页手动清空）。
    public func clear() {
        flushTask?.cancel()
        flushTask = nil
        pendingSegments.removeAll(keepingCapacity: true)
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

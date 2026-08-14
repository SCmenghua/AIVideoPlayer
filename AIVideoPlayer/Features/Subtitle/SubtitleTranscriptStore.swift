import Foundation
import Observation

/// 共享字幕记录存储（Phase 8.12 性能优化）：
/// - 字幕管线的每一条识别 / 翻译结果（原文 + 译文）写入这里，作为唯一数据源；
/// - 播放器 Overlay 按播放光标实时查询，设置页「字幕记录」卡片展示最近条目；
/// - 有界存储（只保留 final），streaming partial 只作为单条当前预览，
///   避免同一窗口的逐词更新污染时间轴、造成无界增长。
/// - **批量更新 + 节流**：避免每次 append 都触发 @Observable 的 UI 刷新，
///   防止高频识别结果卡死主线程。
@MainActor
@Observable
public final class SubtitleTranscriptStore {
    /// 最多保留的字幕条数（设置页调试查看窗口）。
    public static let maxStoredSegments = 200

    public private(set) var segments: [SubtitleSegment] = []
    /// 当前 Whisper streaming preview。它不属于历史时间轴，也不会计入字幕记录条数。
    public private(set) var previewSegment: SubtitleSegment?

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
        if segment.isPartial {
            updatePreview(segment)
            return
        }
        if let previewSegment, Self.overlaps(previewSegment, segment) {
            self.previewSegment = nil
        }
        pendingSegments.append(segment)
        scheduleFlush()
    }

    /// 用同一识别窗口的最新 partial 覆盖当前预览，而非持续追加字幕记录。
    public func updatePreview(_ segment: SubtitleSegment) {
        guard segment.isPartial else {
            append(segment)
            return
        }
        previewSegment = segment
    }

    /// seek、换片、关闭字幕或相应 final 到达时移除临时预览。
    public func clearPreview() {
        previewSegment = nil
    }

    /// 立即刷新所有待提交的字幕到 segments（触发 UI 更新）。
    /// 按 id 更新某条已写入字幕的译文（批量翻译回填用，Phase 9.3.2）。
    /// 返回该字幕的原文；找不到对应字幕时返回 nil。
    @discardableResult
    public func updateTranslation(id: UUID, translatedText: String) -> String? {
        if !pendingSegments.isEmpty { flush() }
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let original = segments[index].originalText
        var updated = segments[index]
        updated.translatedText = translatedText
        segments[index] = updated
        return original
    }
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
            insertSorted(segment)
        }

        pendingSegments.removeAll(keepingCapacity: true)
        trimIfNeeded()
        lastFlushTime = .now
    }

    /// 当前时刻应显示的字幕：时间轴 final 优先；没有命中时才显示当前窗口的单条预览。
    /// 查询时会先将待提交的字幕合并到主存储，确保最新结果立即可见。
    public func segment(at time: TimeInterval) -> SubtitleSegment? {
        // 查询前先刷新缓冲区，确保最新字幕立即可见（不等待定时器）
        if !pendingSegments.isEmpty {
            flush()
        }

        let candidates = segments.filter {
            $0.startTime <= time && time < Self.displayEndTime(of: $0)
        }
        if let final = candidates.last {
            return final
        }
        guard let previewSegment,
              previewSegment.startTime <= time,
              time < Self.displayEndTime(of: previewSegment)
        else {
            return nil
        }
        return previewSegment
    }

    /// 清空全部记录（播放器换片 / 管线关闭 / 设置页手动清空）。
    public func clear() {
        Log.app.debug("字幕存储已清空（clear）")
        flushTask?.cancel()
        flushTask = nil
        pendingSegments.removeAll(keepingCapacity: true)
        segments.removeAll(keepingCapacity: true)
        previewSegment = nil
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

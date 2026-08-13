import Foundation
import Observation

/// 批量翻译协调器（Phase 9.3.1）。
/// 收集 final 字幕段，按「水位线 + 批量窗口」策略把多条字幕打包成一次翻译请求，
/// 翻译完成后按顺序回填译文。仅用于 LLM 类 Provider。
///
/// 失败约定（Phase 9.3.2）：翻译失败时不回填译文，仅记录错误并结束本批，
/// 已写入字幕存储的原文保持不变（Overlay 会自然回退显示原文）。
@MainActor
@Observable
public final class TranslationBatchCoordinator {

    public struct Configuration: Sendable {
        /// 一次批量翻译的最大内容时长（秒）。
        public var batchWindow: TimeInterval
        /// 译文字幕储备低于该水位时触发补货。
        public var lowWatermark: TimeInterval
        /// 首次播放前需要凑足的内容时长（秒）。
        public var initialFillDuration: TimeInterval
        /// 单次补货的最小内容时长（秒），避免请求过碎。
        public var minimumBatchDuration: TimeInterval
        /// 单批最多条数（nil = 不限制）。首批拆小用。
        public var maxSegmentsPerBatch: Int?

        public init(
            batchWindow: TimeInterval = 60,
            lowWatermark: TimeInterval = 20,
            initialFillDuration: TimeInterval = 60,
            minimumBatchDuration: TimeInterval = 15,
            maxSegmentsPerBatch: Int? = nil
        ) {
            self.batchWindow = batchWindow
            self.lowWatermark = lowWatermark
            self.initialFillDuration = initialFillDuration
            self.minimumBatchDuration = minimumBatchDuration
            self.maxSegmentsPerBatch = maxSegmentsPerBatch
        }
    }

    public struct PendingItem: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let text: String

        public init(id: UUID, startTime: TimeInterval, endTime: TimeInterval, text: String) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.text = text
        }

        public init(segment: SubtitleSegment) {
            self.init(
                id: segment.id,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.originalText
            )
        }

        public var duration: TimeInterval {
            max(endTime - startTime, 0)
        }
    }

    public let configuration: Configuration
    public private(set) var pendingItems: [PendingItem] = []
    public private(set) var isRequestInFlight = false
    public private(set) var requestCount = 0
    public private(set) var lastBatchDuration: TimeInterval?
    public private(set) var lastError: String?
    public private(set) var didCompleteInitialBatch = false
    /// 已翻译字幕覆盖到的最大时间点（用于计算储备）。
    public private(set) var translatedThrough: TimeInterval = 0

    /// 译文字幕在播放光标之后的储备秒数。
    public var translatedAhead: TimeInterval {
        max(0, translatedThrough - playbackTime)
    }

    private var playbackTime: TimeInterval = 0
    private var generation = 0
    private var inFlightTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    private let translator: @MainActor ([String]) async throws -> [String]
    private let onTranslated: @MainActor ([UUID: String]) -> Void
    private let onInitialBatchCompleted: @MainActor () -> Void

    public init(
        configuration: Configuration = Configuration(),
        translator: @escaping @MainActor ([String]) async throws -> [String],
        onTranslated: @escaping @MainActor ([UUID: String]) -> Void = { _ in },
        onInitialBatchCompleted: @escaping @MainActor () -> Void = {}
    ) {
        self.configuration = configuration
        self.translator = translator
        self.onTranslated = onTranslated
        self.onInitialBatchCompleted = onInitialBatchCompleted
    }

    /// 提交一条 final 字幕（partial 直接忽略）。
    public func submit(_ segment: SubtitleSegment) {
        guard !segment.isPartial else { return }
        pendingItems.append(PendingItem(segment: segment))
        flushIfNeeded()
    }

    /// 更新播放光标；当译文储备不足时触发补货。
    public func updatePlaybackTime(_ time: TimeInterval) {
        playbackTime = max(0, time)
        flushIfNeeded()
    }

    /// 识别停滞 / 音轨耗尽时由管线调用：立即把当前 pending 打包发送，
    /// 用于短视频等「凑不满首批窗口」的场景。
    public func flushPendingNow() {
        guard !isRequestInFlight, !pendingItems.isEmpty else { return }
        startBatch()
    }

    /// 换片 / seek / 切换 Provider：取消进行中的请求并清空队列。
    public func reset() {
        generation += 1
        inFlightTask?.cancel()
        inFlightTask = nil
        retryTask?.cancel()
        retryTask = nil
        consecutiveFailures = 0
        isRequestInFlight = false
        pendingItems.removeAll(keepingCapacity: true)
        playbackTime = 0
        translatedThrough = 0
        didCompleteInitialBatch = false
        lastError = nil
        lastBatchDuration = nil
    }

    // MARK: - Flush

    private func pendingDuration() -> TimeInterval {
        pendingItems.reduce(0) { $0 + max($1.duration, 0.5) }
    }

    private func flushIfNeeded() {
        guard !isRequestInFlight, !pendingItems.isEmpty else { return }

        let duration = pendingDuration()
        let shouldFlush: Bool
        if !didCompleteInitialBatch {
            shouldFlush = duration >= configuration.initialFillDuration
        } else {
            shouldFlush = duration >= configuration.batchWindow
                || (translatedAhead < configuration.lowWatermark
                    && duration >= configuration.minimumBatchDuration)
        }

        if shouldFlush {
            startBatch()
        }
    }

    private func startBatch() {
        let items = takeBatchItems()
        guard !items.isEmpty else { return }

        isRequestInFlight = true
        requestCount += 1
        let startedAt = Date()
        let batchGeneration = generation

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRequestInFlight = false
                if self.generation == batchGeneration {
                    self.flushIfNeeded()
                }
            }
            do {
                let translations = try await self.translator(items.map(\.text))
                try Task.checkCancellation()
                guard self.generation == batchGeneration else { return }
                let mapping = try self.makeMapping(translations: translations, items: items)
                self.lastBatchDuration = Date().timeIntervalSince(startedAt)
                self.translatedThrough = max(
                    self.translatedThrough,
                    items.map(\.endTime).max() ?? self.translatedThrough
                )
                self.lastError = nil
                self.consecutiveFailures = 0
                self.retryTask?.cancel()
                self.onTranslated(mapping)
                if !self.didCompleteInitialBatch {
                    self.didCompleteInitialBatch = true
                    self.onInitialBatchCompleted()
                }
            } catch is CancellationError {
                // reset / seek 取消：由 reset() 负责清空状态。
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.lastBatchDuration = Date().timeIntervalSince(startedAt)
                if !self.didCompleteInitialBatch {
                    // 首批失败：不放行播放，重排队列并按退避重试（等待门控保持关闭）。
                    self.pendingItems.insert(contentsOf: items, at: 0)
                    self.consecutiveFailures += 1
                    self.scheduleRetry()
                }
                // 后续批次失败：不再重试，对应字幕保持原文显示。
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = min(Double(consecutiveFailures), 5.0) * 2.0
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.flushPendingNow()
        }
    }

    private func takeBatchItems() -> [PendingItem] {
        var selected: [PendingItem] = []
        var duration: TimeInterval = 0
        var index = 0
        let maxCount = configuration.maxSegmentsPerBatch
        while index < pendingItems.count {
            if let maxCount, selected.count >= maxCount { break }
            let item = pendingItems[index]
            let itemDuration = max(item.duration, 0.5)
            if !selected.isEmpty && duration + itemDuration > configuration.batchWindow {
                break
            }
            selected.append(item)
            duration += itemDuration
            index += 1
            if duration >= configuration.batchWindow {
                break
            }
        }
        if selected.isEmpty, let first = pendingItems.first {
            selected = [first]
            index = 1
        }
        pendingItems.removeFirst(index)
        return selected
    }

    private func makeMapping(
        translations: [String],
        items: [PendingItem]
    ) throws -> [UUID: String] {
        guard translations.count == items.count else {
            throw TranslationBatchError.mismatchedCount(
                expected: items.count,
                actual: translations.count
            )
        }
        var mapping: [UUID: String] = [:]
        mapping.reserveCapacity(items.count)
        for (item, text) in zip(items, translations) {
            mapping[item.id] = text
        }
        return mapping
    }
}
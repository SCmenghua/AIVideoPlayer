import Foundation
import Observation

/// AI 字幕子系统（Phase 5 真实实现）。
/// 持有识别器 + 音频管线，维护领先识别游标（只进不退）：
/// - 超前模式（可预读来源 + 开关开启）：窗口整句 final，识别游标领先播放光标 Δ；
/// - 原始路径（开关关闭 / 麦克风 / 实时 Tap）：partial → final 实时输出。
/// 状态语义：LISTENING / TRANSCRIBING / TRANSLATING 表示领先窗口内的管线状态，
/// READY 表示当前播放位置的句子已整句就绪。
@MainActor
@Observable
public class SubtitlePipeline: SubtitleStatusProviding {
    public private(set) var status: AISubtitleStatus
    public let statusStream: AsyncStream<AISubtitleStatus>
    public let segments: AsyncStream<SubtitleSegment>

    private let settings: SubtitleSettings
    private let translationSettings: TranslationSettings
    private let translationProviderFactory: @MainActor (TranslationSettings) -> (any TranslationEngine)?
    private let contextProvider: TranslationContextProvider
    private let recognizerFactory: @MainActor () -> any SpeechRecognizer
    private let playerSourceFactory: @MainActor (any PlaybackEngine) -> any AudioPipeline
    private let readerSourceFactory: @MainActor (MediaItem) -> any AudioPipeline

    private var recognizer: (any SpeechRecognizer)?
    private var source: (any AudioPipeline)?
    private var engine: (any PlaybackEngine)?
    /// 当前音频来源绑定的媒体 ID：用于换片检测（避免把上一部视频的
    /// 音频识别结果写到新视频的时间线上）。
    private var sourceItemID: UUID?
    private let buffer = PCMBuffer()
    private var generation = 0
    private var active = false
    private var modelLoaded = false
    private var currentLanguage: String?
    private var playbackTime: TimeInterval = 0
    private var loopTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var forwardTask: Task<Void, Never>?
    private var cachedTranslationEngine: (any TranslationEngine)?
    private var cachedEngineKey: String?

    private let statusContinuation: AsyncStream<AISubtitleStatus>.Continuation
    private let segmentsContinuation: AsyncStream<SubtitleSegment>.Continuation

    /// 是否已启用。
    public var isActive: Bool {
        active
    }

    public init(
        settings: SubtitleSettings,
        translationSettings: TranslationSettings = TranslationSettings(),
        translationProviderFactory: @escaping @MainActor (TranslationSettings) -> (any TranslationEngine)? = {
            TranslationProviderFactory.make(settings: $0)
        },
        contextProvider: TranslationContextProvider = TranslationContextProvider(),
        recognizerFactory: @escaping @MainActor () -> any SpeechRecognizer = { WhisperKitSpeechRecognizer() },
        playerSourceFactory: @escaping @MainActor (any PlaybackEngine) -> any AudioPipeline = { PlayerAudioPipeline(engine: $0) },
        readerSourceFactory: @escaping @MainActor (MediaItem) -> any AudioPipeline = { AssetReaderAudioPipeline(item: $0) }
    ) {
        self.settings = settings
        self.translationSettings = translationSettings
        self.translationProviderFactory = translationProviderFactory
        self.contextProvider = contextProvider
        self.recognizerFactory = recognizerFactory
        self.playerSourceFactory = playerSourceFactory
        self.readerSourceFactory = readerSourceFactory
        self.status = AISubtitleStatus(state: .off, isModelLoaded: false, language: nil)

        let statusPair = AsyncStream<AISubtitleStatus>.makeStream()
        self.statusStream = statusPair.stream
        self.statusContinuation = statusPair.continuation

        let segmentsPair = AsyncStream<SubtitleSegment>.makeStream()
        self.segments = segmentsPair.stream
        self.segmentsContinuation = segmentsPair.continuation
    }

    // MARK: - SubtitleStatusProviding

    public func toggle() async {
        if active {
            await shutdown()
        } else {
            await activate()
        }
    }

    // MARK: - 播放器联动

    public func attach(playbackEngine: any PlaybackEngine) {
        engine = playbackEngine
    }

    public func detachPlaybackEngine() {
        engine = nil
        source = nil
        sourceItemID = nil
    }

    /// 播放开始 / seek 重建 / 恢复播放前调用：确保音频管线与识别循环就绪。
    public func preparePlayback(from time: TimeInterval) async {
        playbackTime = time
        guard active else { return }
        generation += 1
        stopLoops()
        await recognizer?.discardPendingResults()

        guard let engine else { return }
        // 换片：来源绑定的媒体与引擎当前媒体不一致时先停旧来源再重建。
        if engine.currentItem?.id != sourceItemID {
            await source?.stop()
            source = nil
            sourceItemID = engine.currentItem?.id
        }
        if let source {
            await source.reset(to: time)
            try? await source.start(at: time)
        } else {
            self.source = await makeSource(engine: engine, at: time)
        }
        guard let source else { return }

        buffer.reset(to: time)
        consumeChunks(from: source)
        startRecognitionLoop()
    }

    public func handlePlaybackPaused() {
        stopLoops()
    }

    public func handlePlaybackEnded() {
        stopLoops()
    }

    public func handleSeek(to time: TimeInterval) async {
        playbackTime = time
        generation += 1
        stopLoops()
        await recognizer?.discardPendingResults()
        buffer.reset(to: time)
    }

    /// 设置变更（超前开关 / Δ）后重建识别游标并丢弃已缓存的 partial / final。
    public func rebuildAfterSettingsChange() async {
        cachedTranslationEngine = nil
        cachedEngineKey = nil
        guard active else { return }
        generation += 1
        stopLoops()
        await recognizer?.discardPendingResults()
        buffer.reset(to: playbackTime)
        if let source {
            await source.reset(to: playbackTime)
            try? await source.start(at: playbackTime)
        }
        if let source {
            consumeChunks(from: source)
        }
        startRecognitionLoop()
    }

    // MARK: - 超前识别查询

    /// 是否应执行超前模式（开启 + 当前来源可预读）。
    public var shouldUseLeadAhead: Bool {
        active && settings.isLeadAheadEnabled && source?.canReadAhead == true
    }

    public var leadAheadWindow: TimeInterval {
        settings.leadAheadWindow
    }

    /// 等待领先窗口缓冲 Δ 秒（播放器在调用 play() 前使用）。
    public func waitUntilLeadCaptured(delta: TimeInterval, timeout: TimeInterval) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if buffer.capturedEnd - playbackTime >= delta { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return buffer.capturedEnd - playbackTime >= delta
    }

    // MARK: - 激活 / 关闭

    private func activate() async {
        guard !active else { return }
        active = true
        generation += 1
        currentLanguage = nil
        modelLoaded = false
        setStatus(state: .loading)

        let recognizer = recognizerFactory()
        self.recognizer = recognizer
        do {
            try await recognizer.start()
            modelLoaded = true
            startForwarding(recognizer: recognizer)
            setStatus(state: .listening)
            if let engine {
                await preparePlayback(from: playbackTime)
            }
        } catch {
            active = false
            modelLoaded = false
            setStatus(state: .error)
        }
    }

    private func shutdown() async {
        generation += 1
        active = false
        stopLoops()
        forwardTask?.cancel()
        forwardTask = nil
        await recognizer?.stop()
        await source?.stop()
        recognizer = nil
        source = nil
        sourceItemID = nil
        buffer.reset(to: playbackTime)
        setStatus(state: .off)
    }

    /// 过期片段判定容差（秒）：允许轻微的时钟偏差，避免误删边界片段。
    private static let staleSegmentTolerance: TimeInterval = 1

    // MARK: - 管线组装

    private func makeSource(engine: any PlaybackEngine, at time: TimeInterval) async -> (any AudioPipeline)? {
        if let item = engine.currentItem {
            let reader = readerSourceFactory(item)
            if (try? await reader.start(at: time)) != nil {
                return reader
            }
        }
        let tapSource = playerSourceFactory(engine)
        if (try? await tapSource.start(at: time)) != nil {
            return tapSource
        }
        setStatus(state: .error)
        return nil
    }

    private func consumeChunks(from source: any AudioPipeline) {
        consumeTask?.cancel()
        consumeTask = Task { [weak self] in
            for await chunk in source.chunks {
                guard let self, self.active else { return }
                self.buffer.append(chunk)
            }
        }
    }

    private func startRecognitionLoop() {
        loopTask?.cancel()
        let taskGeneration = generation
        loopTask = Task { [weak self] in
            await self?.runRecognitionLoop(generation: taskGeneration)
        }
    }

    private func stopLoops() {
        consumeTask?.cancel()
        consumeTask = nil
        loopTask?.cancel()
        loopTask = nil
    }

    /// 把识别器产出的 SubtitleSegment 转发给管线的 segments 流（Phase 6 消费）。
    private func startForwarding(recognizer: any SpeechRecognizer) {
        forwardTask?.cancel()
        forwardTask = Task { [weak self] in
            for await segment in recognizer.segments {
                guard let self else { return }
                // seek / 暂停恢复后到达的过期结果（时间早于当前播放位置）直接丢弃，
                // 避免旧字幕写入时间线（配合识别器内的 generation 门控双保险）。
                if segment.startTime + Self.staleSegmentTolerance < self.playbackTime {
                    continue
                }
                if segment.isPartial {
                    // 原始实时路径：逐词 partial 原样透出，不做翻译。
                    self.segmentsContinuation.yield(segment)
                } else {
                    // Phase 7：final 段翻译后透出（超前窗口内译文提前就绪）。
                    await self.translateAndYield(segment)
                }
            }
        }
    }

    /// 翻译 final 段并写入 `translatedText`；翻译不可用 / 失败时原样透出
    /// （Overlay 译文缺失只显示原文，不破坏 Phase 6 行为）。
    private func translateAndYield(_ segment: SubtitleSegment) async {
        guard active, translationSettings.isEnabled,
              let engine = makeTranslationEngine()
        else {
            segmentsContinuation.yield(segment)
            return
        }

        let previousState = status.state
        setStatus(state: .translating)
        var translated: String?
        do {
            let context: TranslationContext?
            if translationSettings.isContextPolishEnabled,
               engine.supportsContextPolish,
               contextProvider.hasRecentEntries
            {
                context = contextProvider.makeContext()
            } else {
                context = nil
            }
            translated = try await engine.translate(
                segment.originalText,
                from: currentLanguage,
                to: translationSettings.targetLanguageCode,
                context: context
            )
        } catch {
            // 单句翻译失败不打断字幕：原样透出原文。
            translated = nil
        }
        guard active, !Task.isCancelled else { return }

        if let translated, !translated.isEmpty {
            contextProvider.record(original: segment.originalText, translated: translated)
            var enriched = segment
            enriched.translatedText = translated
            segmentsContinuation.yield(enriched)
        } else {
            segmentsContinuation.yield(segment)
        }

        if status.state == .translating {
            setStatus(state: previousState == .translating ? .ready : previousState)
        }
    }

    private func makeTranslationEngine() -> (any TranslationEngine)? {
        let key = translationSettings.engineCacheKey
        if let cachedTranslationEngine, cachedEngineKey == key {
            return cachedTranslationEngine
        }
        let engine = translationProviderFactory(translationSettings)
        cachedTranslationEngine = engine
        cachedEngineKey = key
        return engine
    }

    private func runRecognitionLoop(generation: Int) async {
        let leadAhead = shouldUseLeadAhead
        let windowSize: TimeInterval = leadAhead ? max(settings.leadAheadWindow, 5) : 5
        var cursor = buffer.captureStart

        while active && self.generation == generation && !Task.isCancelled {
            guard let recognizer else { return }

            guard let samples = buffer.extract(from: cursor, to: cursor + windowSize) else {
                try? await Task.sleep(for: .milliseconds(120))
                continue
            }

            let windowStart = cursor
            cursor += windowSize
            guard !samples.isEmpty else { continue }

            setStatus(state: .transcribing)
            do {
                let outcome = try await recognizer.transcribe(
                    samples: samples,
                    sampleRate: buffer.sampleRateValue,
                    windowStart: windowStart,
                    windowDuration: windowSize,
                    emitPartial: !leadAhead
                )
                guard self.generation == generation else { return }
                if let language = outcome.language, !language.isEmpty {
                    currentLanguage = language
                }
                setStatus(state: outcome.segmentCount > 0 ? .ready : .listening)
            } catch is CancellationError {
                return
            } catch {
                // 单个窗口失败：跳过并继续，避免整条管线停摆。
                setStatus(state: .listening)
            }
        }
    }

    private func setStatus(state: AIState) {
        let newStatus = AISubtitleStatus(
            state: state,
            isModelLoaded: modelLoaded,
            language: currentLanguage
        )
        guard newStatus != status else { return }
        status = newStatus
        statusContinuation.yield(newStatus)
    }
}

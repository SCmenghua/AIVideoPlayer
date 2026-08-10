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
    /// 已完成的识别窗口数（每次成功转写 +1；用户可据此判断识别是否真的在跑）。
    public private(set) var transcribedWindowCount = 0
    /// 已产出并转发给字幕层的 segment 数（partial / final 均计入）。
    public private(set) var emittedSegmentCount = 0
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
        Log.app.debug("字幕管线 preparePlayback from=\(time, format: .fixed(precision: 1)) active=\(self.active)")
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
        Log.app.debug("字幕音频来源就绪 kind=\(source.sourceKind == .microphone ? "mic" : "player") canReadAhead=\(source.canReadAhead)")

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

    /// 播放器进度回调：更新当前播放位置。
    /// 识别循环据此跳过已落后于播放光标的窗口，避免模型转写速度
    /// 跟不上播放时字幕持续错过（表现为「开了字幕却什么都没有」）。
    public func updatePlaybackPosition(_ time: TimeInterval) {
        playbackTime = time
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
        // 设置变更发生在播放中途时，playbackTime 可能停留在上次播放开始位置，
        // 必须用引擎当前真实时间重建游标，否则识别会从旧位置开始而永远追不上。
        let resumeTime = engine?.currentTime ?? playbackTime
        buffer.reset(to: resumeTime)
        if let source {
            await source.reset(to: resumeTime)
            try? await source.start(at: resumeTime)
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
        Log.app.info("激活字幕管线")
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
            if engine != nil {
                // 播放中途才打开字幕时，engine.currentTime 才是真实播放位置；
                // playbackTime 可能停留在更早的记录值，用它重建会让识别
                // 从旧位置开始、永远追不上播放光标（表现为没有任何字幕）。
                await preparePlayback(from: engine?.currentTime ?? playbackTime)
            }
        } catch {
            Log.app.error("字幕管线激活失败：\(error.localizedDescription)")
            active = false
            modelLoaded = false
            setStatus(state: .error)
        }
    }

    private func shutdown() async {
        Log.app.info("关闭字幕管线")
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
                    self.forwardSegment(segment)
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
            forwardSegment(segment)
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
                from: translationSettings.sourceLanguageCode ?? currentLanguage,
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
            forwardSegment(enriched)
        } else {
            forwardSegment(segment)
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

    /// 转发 segment 到字幕流并累计统计。
    private func forwardSegment(_ segment: SubtitleSegment) {
        emittedSegmentCount += 1
        segmentsContinuation.yield(segment)
    }

    private func runRecognitionLoop(generation: Int) async {
        let leadAhead = shouldUseLeadAhead
        let windowSize: TimeInterval = leadAhead ? max(settings.leadAheadWindow, 5) : 5
        var cursor = buffer.captureStart

        while active && self.generation == generation && !Task.isCancelled {
            guard let recognizer else { return }

            // 识别速度跟不上播放时，跳过已落后的窗口：从当前播放位置继续，
            // 避免把算力浪费在已经播过的音频上（字幕内容会从当前位置开始出现）。
            if cursor + windowSize <= playbackTime - Self.staleSegmentTolerance {
                let oldCursor = cursor
                cursor = max(playbackTime, buffer.captureStart)
                Log.app.debug("跳过落后识别窗口：\(oldCursor, format: .fixed(precision: 1))s → 播放位置 \(self.playbackTime, format: .fixed(precision: 1))s")
            }

            guard let samples = buffer.extract(from: cursor, to: cursor + windowSize) else {
                // 音频尚未缓冲到目标窗口：节流记录，便于确认识别等待的是音频还是模型。
                logBufferWaitIfNeeded(windowStart: cursor)
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
                    language: currentLanguage,
                    emitPartial: !leadAhead
                )
                guard self.generation == generation else { return }
                if let language = outcome.language, !language.isEmpty {
                    currentLanguage = language
                }
                transcribedWindowCount += 1
                Log.app.debug("识别窗口 \(windowStart, format: .fixed(precision: 1))s 完成：segments=\(outcome.segmentCount) language=\(self.currentLanguage ?? "nil")")
                setStatus(state: outcome.segmentCount > 0 ? .ready : .listening)
            } catch is CancellationError {
                // 真正的取消：循环任务被 stopLoops / 换片 / seek 取消，
                // 或 generation 已变化（新会话接管），此时才应退出。
                if Task.isCancelled || self.generation != generation || !self.active {
                    return
                }
                // 其余 CancellationError 视作临时不可用：稍后重试，不终止循环。
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                // 单个窗口失败（含模型尚未就绪）：跳过并继续，避免整条管线停摆。
                setStatus(state: .listening)
                try? await Task.sleep(for: .milliseconds(100))
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

    /// 音频缓冲等待日志（节流：状态变化或每 3 秒一次，避免刷屏）。
    private var lastBufferWaitLog: TimeInterval = -.infinity

    private func logBufferWaitIfNeeded(windowStart: TimeInterval) {
        let now = Date().timeIntervalSince1970
        guard now - lastBufferWaitLog >= 3 else { return }
        lastBufferWaitLog = now
        Log.app.debug("等待音频缓冲：目标窗口 \(windowStart, format: .fixed(precision: 1))s，已捕获到 \(self.buffer.capturedEnd, format: .fixed(precision: 1))s")
    }
}

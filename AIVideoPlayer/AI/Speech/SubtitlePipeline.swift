import Foundation
import Observation

/// AI 字幕子系统（Phase 8.5 重构）。
/// 持有识别器 + 音频管线，实时转写路径：固定 5 秒窗口 partial → final 输出；
/// 识别游标只进不退、落后于播放光标的窗口跳过（避免识别速度跟不上时字幕持续错过）。
/// 每一条结果（原文 + 译文）写入共享 `SubtitleTranscriptStore`，
/// 播放器 Overlay 与设置页「字幕记录」都从该存储读取，不再依赖单次消费的流。
@MainActor
@Observable
public class SubtitlePipeline: SubtitleStatusProviding {
    public private(set) var status: AISubtitleStatus
    /// 已完成的识别窗口数（每次成功转写 +1；用户可据此判断识别是否真的在跑）。
    public private(set) var transcribedWindowCount = 0
    /// 已产出并写入字幕记录的字幕条数（partial / final 均计入）。
    public private(set) var emittedSegmentCount = 0
    /// 已成功翻译并写入译文的字幕条数（final 段，翻译成功 +1）。
    public private(set) var translatedSegmentCount = 0
    /// 最近一次翻译失败原因（成功 / 尚未翻译时为 nil），供设置页诊断展示。
    public private(set) var lastTranslationError: String?
    public let statusStream: AsyncStream<AISubtitleStatus>

    private let translationSettings: TranslationSettings
    private let translationProviderFactory: @MainActor (TranslationSettings) -> (any TranslationEngine)?
    private let contextProvider: TranslationContextProvider
    private let recognizerFactory: @MainActor () -> any SpeechRecognizer
    private let playerSourceFactory: @MainActor (any PlaybackEngine) -> any AudioPipeline
    private let readerSourceFactory: @MainActor (MediaItem) -> any AudioPipeline
    private let transcript: SubtitleTranscriptStore

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

    /// 是否已启用。
    public var isActive: Bool {
        active
    }

    public init(
        transcript: SubtitleTranscriptStore = SubtitleTranscriptStore(),
        translationSettings: TranslationSettings = TranslationSettings(),
        translationProviderFactory: @escaping @MainActor (TranslationSettings) -> (any TranslationEngine)? = {
            TranslationProviderFactory.make(settings: $0)
        },
        contextProvider: TranslationContextProvider = TranslationContextProvider(),
        recognizerFactory: @escaping @MainActor () -> any SpeechRecognizer = { WhisperKitSpeechRecognizer() },
        playerSourceFactory: @escaping @MainActor (any PlaybackEngine) -> any AudioPipeline = { PlayerAudioPipeline(engine: $0) },
        readerSourceFactory: @escaping @MainActor (MediaItem) -> any AudioPipeline = { AssetReaderAudioPipeline(item: $0) }
    ) {
        self.transcript = transcript
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
        Log.app.debug("字幕管线 preparePlayback from=\(String(format: "%.1f", time)) active=\(self.active)")
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
        Log.app.debug("字幕音频来源就绪 kind=\(source.sourceKind == .microphone ? "mic" : "player")")

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

    /// 翻译设置变更后刷新：丢弃缓存的翻译引擎，下次翻译按新设置重建。
    public func rebuildTranslationEngine() {
        cachedTranslationEngine = nil
        cachedEngineKey = nil
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
        // 确保所有待提交的字幕都已写入
        transcript.flush()
        setStatus(state: .off)
    }

    /// 过期片段判定容差（秒）：允许轻微的时钟偏差，避免误删边界片段。
    private static let staleSegmentTolerance: TimeInterval = 1

    // MARK: - 管线组装

    private func makeSource(engine: any PlaybackEngine, at time: TimeInterval) async -> (any AudioPipeline)? {
        guard let item = engine.currentItem else {
            await setStatus(state: .error)
            return nil
        }

        // 本地文件 / 非 HLS 远程文件：优先尝试 AssetReader（预读，识别速度快）。
        // 网络流媒体（HLS 等）：直接用 PlayerAudioPipeline（实时 Tap），
        // 避免 AVAssetReader 不支持 HLS 导致卡住或失败。
        let isLocalFile = item.url.isFileURL
        let isHLS = item.url.pathExtension.lowercased() == "m3u8"
            || item.url.absoluteString.contains(".m3u8")

        if isLocalFile && !isHLS {
            // 本地文件：优先用 AssetReader 预读。
            let reader = await readerSourceFactory(item)
            if (try? await reader.start(at: time)) != nil {
                return reader
            }
        }

        // 网络资源 / HLS / AssetReader 失败回退：用实时 Tap。
        let tapSource = await playerSourceFactory(engine)
        if (try? await tapSource.start(at: time)) != nil {
            return tapSource
        }

        await setStatus(state: .error)
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

    /// 把识别器产出的 SubtitleSegment 写入共享字幕记录（Overlay 与设置页读取）。
    private func startForwarding(recognizer: any SpeechRecognizer) {
        forwardTask?.cancel()
        forwardTask = Task { [weak self] in
            for await segment in recognizer.segments {
                guard let self else { return }
                if segment.isPartial {
                    // 实时路径 partial 原样写入：窗口内整句显示，final 到达后由存储收敛。
                    // 不按播放位置丢弃 partial，避免识别稍慢时「识别已产出但播放器无字幕」。
                    await self.forwardSegment(segment)
                } else {
                    // final 只丢弃整句已播完的过期结果（seek / 暂停恢复竞态）。
                    let playbackTime = await self.playbackTime
                    if segment.endTime + Self.staleSegmentTolerance < playbackTime {
                        continue
                    }
                    await self.translateAndYield(segment)
                }
            }
        }
    }

    /// 翻译 final 段并写入 `translatedText`；翻译不可用 / 失败时原样写入
    /// （Overlay 译文缺失只显示原文，不破坏原有行为）。
    /// 翻译在后台线程执行，避免阻塞主线程 UI。
    private func translateAndYield(_ segment: SubtitleSegment) async {
        guard await active, await translationSettings.isEnabled,
              let engine = await makeTranslationEngine()
        else {
            await forwardSegment(segment)
            return
        }

        let effectiveSource = await effectiveTranslationSource
        let targetLang = await translationSettings.targetLanguageCode
        Log.app.debug("开始翻译 final 段 start=\(String(format: "%.1f", segment.startTime))s 源=\(effectiveSource ?? "nil") 目标=\(targetLang) 文本=\(segment.originalText.prefix(40))")
        let previousState = await status.state
        await setStatus(state: .translating)

        // 翻译在后台线程执行，避免阻塞主线程（系统翻译可能耗时数百毫秒）。
        let sourceLanguage = effectiveSource
        let targetLanguage = targetLang
        let originalText = segment.originalText
        let context: TranslationContext?
        let translationSettings = await self.translationSettings
        let contextProvider = await self.contextProvider
        if translationSettings.isContextPolishEnabled,
           engine.supportsContextPolish,
           contextProvider.hasRecentEntries
        {
            context = contextProvider.makeContext()
        } else {
            context = nil
        }

        let translated: String? = await Task.detached {
            do {
                return try await engine.translate(
                    originalText,
                    from: sourceLanguage,
                    to: targetLanguage,
                    context: context
                )
            } catch {
                // 错误在主线程记录
                await MainActor.run {
                    self.lastTranslationError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    Log.app.error("翻译失败：\(self.lastTranslationError ?? "未知错误")（源=\(sourceLanguage ?? "nil")，目标=\(targetLanguage)）")
                }
                return nil
            }
        }.value

        guard await active, !Task.isCancelled else { return }

        if let translated, !translated.isEmpty {
            await MainActor.run {
                self.translatedSegmentCount += 1
                self.lastTranslationError = nil
                self.contextProvider.record(original: segment.originalText, translated: translated)
            }
            var enriched = segment
            enriched.translatedText = translated
            await forwardSegment(enriched)
        } else {
            await forwardSegment(segment)
        }

        let currentState = await status.state
        if currentState == .translating {
            await setStatus(state: previousState == .translating ? .ready : previousState)
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

    /// 翻译源语言：手动选择 → 翻译代码；自动检测 → 识别语言对应的翻译代码。
    private var effectiveTranslationSource: String? {
        TranslationSourceLanguageCatalog.translationCode(
            for: translationSettings.sourceLanguageCode,
            detected: currentLanguage
        )
    }

    /// 识别语言：手动选择 → Whisper 代码；自动检测 → 已检测语言（首窗 nil 自动检测）。
    private var effectiveRecognitionLanguage: String? {
        TranslationSourceLanguageCatalog.recognitionCode(
            for: translationSettings.sourceLanguageCode,
            detected: currentLanguage
        )
    }

    /// 写入字幕记录并累计统计。
    private func forwardSegment(_ segment: SubtitleSegment) async {
        await MainActor.run {
            self.emittedSegmentCount += 1
            self.transcript.append(segment)
        }
    }

    nonisolated private func runRecognitionLoop(generation: Int) async {
        let windowSize: TimeInterval = 5
        // 识别前瞻窗口：只识别当前播放位置前后各 10 秒的内容，避免无限识别整个视频
        let maxLookahead: TimeInterval = 10
        var cursor = await buffer.captureStart

        while await active && await self.generation == generation && !Task.isCancelled {
            guard let recognizer = await self.recognizer else { return }

            // 识别速度跟不上播放时，跳过已落后的窗口：从当前播放位置继续，
            // 避免把算力浪费在已经播过的音频上（字幕内容会从当前位置开始出现）。
            let playbackTime = await self.playbackTime
            if cursor + windowSize <= playbackTime - Self.staleSegmentTolerance {
                let oldCursor = cursor
                let captureStart = await buffer.captureStart
                cursor = max(playbackTime, captureStart)
                Log.app.debug("跳过落后识别窗口：\(String(format: "%.1f", oldCursor))s → 播放位置 \(String(format: "%.1f", playbackTime))s")
            }

            // 限制识别进度：只识别播放位置前方 maxLookahead 秒内的音频，
            // 避免本地视频无限向后识别导致长视频 UI 卡死。
            if cursor > playbackTime + maxLookahead {
                Log.app.debug("识别已超前播放位置 \(String(format: "%.1f", maxLookahead))s，等待播放追上")
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }

            guard let samples = await buffer.extract(from: cursor, to: cursor + windowSize) else {
                // 音频尚未缓冲到目标窗口：节流记录，便于确认识别等待的是音频还是模型。
                await logBufferWaitIfNeeded(windowStart: cursor)
                try? await Task.sleep(for: .milliseconds(120))
                continue
            }

            let windowStart = cursor
            guard !samples.isEmpty else {
                cursor += windowSize
                continue
            }

            await setStatus(state: .transcribing)
            do {
                let sampleRate = await buffer.sampleRateValue
                let effectiveLang = await effectiveRecognitionLanguage
                let outcome = try await recognizer.transcribe(
                    samples: samples,
                    sampleRate: sampleRate,
                    windowStart: windowStart,
                    windowDuration: windowSize,
                    language: effectiveLang,
                    emitPartial: true
                )
                guard await self.generation == generation else { return }
                if let language = outcome.language, !language.isEmpty {
                    await MainActor.run { self.currentLanguage = language }
                }
                await MainActor.run {
                    self.transcribedWindowCount += 1
                }
                Log.app.debug("识别窗口 \(String(format: "%.1f", windowStart))s 完成：segments=\(outcome.segmentCount) language=\(await self.currentLanguage ?? "nil")")
                await setStatus(state: outcome.segmentCount > 0 ? .ready : .listening)
                // 识别成功，推进到下一个窗口
                cursor += windowSize
            } catch is CancellationError {
                // 真正的取消：循环任务被 stopLoops / 换片 / seek 取消，
                // 或 generation 已变化（新会话接管），此时才应退出。
                if Task.isCancelled || await self.generation != generation || await !self.active {
                    return
                }
                // 其余 CancellationError 视作临时不可用：重试当前窗口，不推进 cursor
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                // 单个窗口失败（含模型尚未就绪）：重试当前窗口，不推进 cursor
                await setStatus(state: .listening)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    nonisolated private func setStatus(state: AIState) async {
        await MainActor.run {
            let newStatus = AISubtitleStatus(
                state: state,
                isModelLoaded: self.modelLoaded,
                language: self.currentLanguage
            )
            guard newStatus != self.status else { return }
            self.status = newStatus
            self.statusContinuation.yield(newStatus)
        }
    }

    /// 音频缓冲等待日志（节流：状态变化或每 3 秒一次，避免刷屏）。
    private var lastBufferWaitLog: TimeInterval = -.infinity

    nonisolated private func logBufferWaitIfNeeded(windowStart: TimeInterval) async {
        let now = Date().timeIntervalSince1970
        let shouldLog = await MainActor.run {
            let should = now - self.lastBufferWaitLog >= 3
            if should {
                self.lastBufferWaitLog = now
            }
            return should
        }
        guard shouldLog else { return }
        let capturedEnd = await buffer.capturedEnd
        Log.app.debug("等待音频缓冲：目标窗口 \(String(format: "%.1f", windowStart))s，已捕获到 \(String(format: "%.1f", capturedEnd))s")
    }
}

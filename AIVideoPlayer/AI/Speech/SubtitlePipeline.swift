import Foundation
import Observation

/// AI 字幕子系统（Phase 8.5 重构）。
/// 持有识别器 + 音频管线，实时转写路径：按语音停顿切分窗口并输出 partial → final；
/// 识别游标只进不退，仅在明显落后时才重同步（避免识别速度跟不上时频繁跳过）。
/// final 结果（原文 + 译文）写入共享 `SubtitleTranscriptStore`，
/// partial 仅作为单条当前预览，
/// 播放器 Overlay 与设置页「字幕记录」都从该存储读取，不再依赖单次消费的流。
@MainActor
@Observable
public class SubtitlePipeline: SubtitleStatusProviding {
    public private(set) var status: AISubtitleStatus
    /// 已完成的识别窗口数（每次成功转写 +1；用户可据此判断识别是否真的在跑）。
    public private(set) var transcribedWindowCount = 0
    /// 已产出并写入字幕记录的 final 字幕条数。
    public private(set) var emittedSegmentCount = 0
    /// 已成功翻译并写入译文的字幕条数（final 段，翻译成功 +1）。
    public private(set) var translatedSegmentCount = 0
    /// 最近一次翻译失败原因（成功 / 尚未翻译时为 nil），供设置页诊断展示。
    public private(set) var lastTranslationError: String?
    /// 是否正在使用批量翻译（仅 LLM 类 Provider，Phase 9.3.2）。
    public private(set) var isUsingBatchTranslation = false
    /// 首批批量翻译是否已完成（用于播放前等待门控）。
    public private(set) var initialBatchCompleted = false
    public let statusStream: AsyncStream<AISubtitleStatus>

    private let translationSettings: TranslationSettings
    private let translationProviderFactory: @MainActor (TranslationSettings) -> (any TranslationEngine)?
    private let contextProvider: TranslationContextProvider
    private let recognizerFactory: @MainActor () -> any SpeechRecognizer
    private let playerSourceFactory: @MainActor (any PlaybackEngine) -> any AudioPipeline
    private let readerSourceFactory: @MainActor (MediaItem) -> any AudioPipeline
    private let transcript: SubtitleTranscriptStore
    private let speechWindowPlanner = SpeechWindowPlanner()

    private var recognizer: (any SpeechRecognizer)?
    private var source: (any AudioPipeline)?
    private var engine: (any PlaybackEngine)?
    /// 当前音频来源绑定的媒体 ID：用于换片检测（避免把上一部视频的
    /// 音频识别结果写到新视频的时间线上）。
    private var sourceItemID: UUID?
    private let buffer = PCMBuffer()
    private var generation = 0
    private var recognitionSessionID = 0
    private var active = false
    private var modelLoaded = false
    private var currentLanguage: String?
    private var playbackTime: TimeInterval = 0
    private var loopTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var forwardTask: Task<Void, Never>?
    private var cachedTranslationEngine: (any TranslationEngine)?
    private var cachedEngineKey: String?
    private var batchCoordinator: TranslationBatchCoordinator?
    /// 当前音频来源是否可预读（AssetReader 可预读；实时 Tap 不可）。
    private var sourceCanPreload = false
    /// 识别最后一次取得进展的时间（用于判断「识别停滞」）。
    private var lastRecognitionProgressTime: Date?
    /// 本代识别循环是否已因停滞触发过 flush。
    private var didNotifyStalledForGeneration = false
    /// 已跳过的落后识别窗口数（统计用）。
    private var skippedWindowCount = 0
    /// 跳过落后窗口累计跳过的秒数。
    private var totalSkippedSeconds: TimeInterval = 0
    /// 「等待播放追上」日志节流时间戳。
    private var lastAheadWaitLog: TimeInterval = -.infinity

    private let statusContinuation: AsyncStream<AISubtitleStatus>.Continuation

    /// 是否已启用。
    public var isActive: Bool {
        active
    }

    /// 播放前是否需要等待首批批量翻译（仅 LLM 模式 + 可预读来源）。
    public var shouldWaitBeforePlayback: Bool {
        active && isUsingBatchTranslation && !initialBatchCompleted && sourceCanPreload
    }

    /// 播放前等待时的提示文案（Phase 9.3.2）。
    public var translationWaitReason: String? {
        shouldWaitBeforePlayback ? "正在等待大模型返回结果…" : nil
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
        transcript.clearPreview()
    }

    /// 播放开始 / seek 重建 / 恢复播放前调用：确保音频管线与识别循环就绪。
    public func preparePlayback(from time: TimeInterval) async {
        playbackTime = time
        guard active else { return }
        Log.app.debug("字幕管线 preparePlayback from=\(String(format: "%.1f", time)) active=\(self.active)")
        generation += 1
        recognitionSessionID += 1
        transcript.clearPreview()
        lastRecognitionProgressTime = nil
        didNotifyStalledForGeneration = false
        stopLoops()
        await recognizer?.discardPendingResults()

        guard let engine else { return }
        // 换片：来源绑定的媒体与引擎当前媒体不一致时先停旧来源再重建。
        if engine.currentItem?.id != sourceItemID {
            await source?.stop()
            source = nil
            sourceItemID = engine.currentItem?.id
            sourceCanPreload = false
            transcript.clear()
            batchCoordinator?.reset()
            initialBatchCompleted = false
        }
        if let source {
            await source.reset(to: time)
            try? await source.start(at: time)
        } else {
            self.source = await makeSource(engine: engine, at: time)
        }
        guard let source else { return }
        source.setReadTarget(time + readAheadLimit)
        Log.app.debug("字幕音频来源就绪 kind=\(source.sourceKind == .microphone ? "mic" : "player") 预读目标=\(String(format: "%.1f", time + readAheadLimit))s")

        buffer.reset(to: time)
        consumeChunks(from: source)
        startRecognitionLoop()
    }

    public func handlePlaybackPaused() {
        stopLoops()
        transcript.clearPreview()
    }

    public func handlePlaybackEnded() {
        stopLoops()
        recognitionSessionID += 1
        transcript.clearPreview()
        batchCoordinator?.reset()
        initialBatchCompleted = false
        lastRecognitionProgressTime = nil
        didNotifyStalledForGeneration = false
    }

    /// 播放器进度回调：更新当前播放位置。
    /// 识别循环据此跳过已落后于播放光标的窗口，避免模型转写速度
    /// 跟不上播放时字幕持续错过（表现为「开了字幕却什么都没有」）。
    public func updatePlaybackPosition(_ time: TimeInterval) {
        playbackTime = time
        // 推进预读目标，让 AssetReader 保持有限前瞻，而不是整轨解码。
        source?.setReadTarget(time + readAheadLimit)
        batchCoordinator?.updatePlaybackTime(time)
    }

    public func handleSeek(to time: TimeInterval) async {
        playbackTime = time
        generation += 1
        recognitionSessionID += 1
        lastRecognitionProgressTime = nil
        didNotifyStalledForGeneration = false
        stopLoops()
        await recognizer?.discardPendingResults()
        buffer.reset(to: time)
        source?.setReadTarget(time + readAheadLimit)
        batchCoordinator?.reset()
        initialBatchCompleted = false
        transcript.clearPreview()
    }

    /// 翻译设置变更后刷新：丢弃缓存的翻译引擎，下次翻译按新设置重建。
    public func rebuildTranslationEngine() {
        cachedTranslationEngine = nil
        cachedEngineKey = nil
        rebuildBatchCoordinator()
    }

    // MARK: - 激活 / 关闭

    private func activate() async {
        guard !active else { return }
        Log.app.info("激活字幕管线")
        active = true
        generation += 1
        recognitionSessionID += 1
        rebuildBatchCoordinator()
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
        recognitionSessionID += 1
        active = false
        stopLoops()
        forwardTask?.cancel()
        forwardTask = nil
        await recognizer?.stop()
        await source?.stop()
        recognizer = nil
        source = nil
        sourceItemID = nil
        sourceCanPreload = false
        batchCoordinator?.reset()
        batchCoordinator = nil
        isUsingBatchTranslation = false
        initialBatchCompleted = false
        buffer.reset(to: playbackTime)
        // 确保所有待提交的字幕都已写入，然后清空当前字幕记录。
        transcript.flush()
        transcript.clear()
        setStatus(state: .off)
    }

    /// 识别允许的最大落后秒数；超过后才重同步到当前播放位置。
    private static let maximumRecognitionLag: TimeInterval = 10
    /// 识别前瞻上限（秒）：大模型批量模式放宽到 60s（Phase 9.3.3），普通模式保持 10s。
    private var recognitionLookahead: TimeInterval {
        isUsingBatchTranslation ? 60 : 10
    }

    /// 预读前瞻上限（秒）：AssetReader 只预读播放位置前方这么多音频。
    /// 大模型批量模式放宽到 70s，普通模式保持 30s，避免整轨解码卡死。
    private var readAheadLimit: TimeInterval {
        isUsingBatchTranslation ? 70 : 30
    }

    // MARK: - 管线组装

    private func makeSource(engine: any PlaybackEngine, at time: TimeInterval) async -> (any AudioPipeline)? {
        guard let item = engine.currentItem else {
            setStatus(state: .error)
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
            let reader = readerSourceFactory(item)
            if (try? await reader.start(at: time)) != nil {
                sourceCanPreload = true
                return reader
            }
        }

        // 网络资源 / HLS / AssetReader 失败回退：用实时 Tap。
        let tapSource = playerSourceFactory(engine)
        if (try? await tapSource.start(at: time)) != nil {
            sourceCanPreload = false
            return tapSource
        }

        sourceCanPreload = false
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
        let taskSessionID = recognitionSessionID
        loopTask = Task { [weak self] in
            await self?.runRecognitionLoop(
                generation: taskGeneration,
                recognitionSessionID: taskSessionID
            )
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
                guard segment.recognitionSessionID == nil
                    || segment.recognitionSessionID == self.recognitionSessionID
                else { continue }
                if segment.isPartial {
                    // partial 仅覆盖当前预览，不进入历史时间轴。
                    self.transcript.updatePreview(segment)
                } else {
                    // final 由识别会话而非播放位置判定有效性，避免慢结果被误丢弃。
                    self.transcript.clearPreview()
                    self.handleFinalSegment(segment, recognitionSessionID: self.recognitionSessionID)
                }
            }
        }
    }

    /// final 已先写入时间轴；翻译完成后按相同 ID 回填译文，绝不阻塞识别结果消费。
    private func translateExistingFinal(
        _ segment: SubtitleSegment,
        recognitionSessionID: Int
    ) async {
        guard active,
              self.recognitionSessionID == recognitionSessionID,
              translationSettings.isEnabled,
              let engine = makeTranslationEngine()
        else { return }

        let providerID = engine.providerID.rawValue
        let previousState = status.state
        setStatus(state: .translating)

        // 翻译在后台线程执行，避免阻塞主线程（系统翻译可能耗时数百毫秒）。
        let sourceLanguage = effectiveTranslationSource
        let targetLanguage = translationSettings.targetLanguageCode
        let originalText = segment.originalText
        let translationStarted = Date()
        let context: TranslationContext?
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
                    Log.app.error("翻译失败 provider=\(providerID)：\(self.lastTranslationError ?? "未知错误")（源=\(sourceLanguage ?? "nil")，目标=\(targetLanguage)）")
                }
                return nil
            }
        }.value

        guard active,
              self.recognitionSessionID == recognitionSessionID,
              !Task.isCancelled
        else { return }

        let translationElapsedMs = Int(Date().timeIntervalSince(translationStarted) * 1000)
        Log.app.debug("翻译完成 provider=\(providerID) 源=\(sourceLanguage ?? "nil") 目标=\(targetLanguage) 耗时=\(translationElapsedMs)ms 原文=\(originalText.prefix(40))")

        if let translated, !translated.isEmpty {
            translatedSegmentCount += 1
            lastTranslationError = nil
            contextProvider.record(original: segment.originalText, translated: translated)
            _ = transcript.updateTranslation(id: segment.id, translatedText: translated)
        }

        if status.state == .translating {
            setStatus(state: previousState == .translating ? .ready : previousState)
        }
    }

    /// final 段处理（Phase 9.3.2）：批量翻译模式先写原文再进协调器；
    /// 非批量模式同样先写原文，再异步回填译文。
    private func handleFinalSegment(
        _ segment: SubtitleSegment,
        recognitionSessionID: Int
    ) {
        if isUsingBatchTranslation, let batchCoordinator {
            Log.app.debug("批量模式写入原文 start=\(String(format: "%.1f", segment.startTime))s 原文=\(segment.originalText.prefix(20))")
            forwardSegment(segment)
            batchCoordinator.submit(segment)
            return
        }
        forwardSegment(segment)
        Task { [weak self] in
            await self?.translateExistingFinal(
                segment,
                recognitionSessionID: recognitionSessionID
            )
        }
    }

    /// 依据当前 Provider 重建批量翻译协调器（仅 LLM 类 Provider 启用）。
    private func rebuildBatchCoordinator() {
        batchCoordinator?.reset()
        batchCoordinator = nil
        isUsingBatchTranslation = false
        initialBatchCompleted = false

        guard active, translationSettings.isEnabled,
              let engine = makeTranslationEngine(),
              engine is TranslationBatchCapable
        else { return }

        // 首批填充 60s：与识别前瞻 60s 对齐，播放前先攒出 1 分钟内容再批量翻译。
        let coordinator = TranslationBatchCoordinator(
            configuration: .init(
                batchWindow: 60,
                lowWatermark: 20,
                initialFillDuration: 60,
                minimumBatchDuration: 5,
                maxSegmentsPerBatch: 8
            ),
            translator: { [weak self] texts in
                guard let self,
                      let base = self.makeTranslationEngine(),
                      let engine = base as? TranslationBatchCapable
                else {
                    throw TranslationBatchError.emptyResponse
                }
                let request = TranslationBatchRequest(
                    texts: texts,
                    sourceLanguage: self.effectiveTranslationSource,
                    targetLanguage: self.translationSettings.targetLanguageCode,
                    context: self.makeTranslationContext()
                )
                Log.app.info("批量翻译发送 provider=\(engine.providerID.rawValue) 条数=\(texts.count) 目标=\(request.targetLanguage) 首段=\(texts.first.map { String($0.prefix(20)) } ?? "")")
                let startedAt = Date()
                do {
                    let result = try await engine.translateBatch(request)
                    Log.app.info("批量翻译收到回复 provider=\(engine.providerID.rawValue) 条数=\(result.count) 耗时=\(Int(Date().timeIntervalSince(startedAt) * 1000))ms")
                    return result
                } catch {
                    self.lastTranslationError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    Log.app.error("批量翻译失败 provider=\(engine.providerID.rawValue) 原因=\(self.lastTranslationError ?? "未知错误")")
                    throw error
                }
            },
            onTranslated: { [weak self] mapping in
                guard let self else { return }
                for (id, translated) in mapping {
                    if let original = self.transcript.updateTranslation(
                        id: id, translatedText: translated
                    ) {
                        self.translatedSegmentCount += 1
                        self.contextProvider.record(original: original, translated: translated)
                    }
                }
                self.lastTranslationError = nil
            },
            onInitialBatchCompleted: { [weak self] in
                guard let self else { return }
                self.initialBatchCompleted = true
                if self.status.state == .translating {
                    self.setStatus(state: .ready)
                }
            }
        )
        batchCoordinator = coordinator
        isUsingBatchTranslation = true
    }

    /// 批量翻译的剧情上下文（仅剧情理解润色开启时提供）。
    private func makeTranslationContext() -> TranslationContext? {
        guard translationSettings.isContextPolishEnabled,
              contextProvider.hasRecentEntries else { return nil }
        return contextProvider.makeContext()
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
    private func forwardSegment(_ segment: SubtitleSegment) {
        guard !segment.isPartial else {
            transcript.updatePreview(segment)
            return
        }
        emittedSegmentCount += 1
        transcript.append(segment)
    }

    private func runRecognitionLoop(
        generation: Int,
        recognitionSessionID: Int
    ) async {
        // 识别前瞻窗口：只识别当前播放位置前方 recognitionLookahead 秒内的音频，
        // 避免无限识别整个视频；大模型批量模式放宽到 60s 以便攒出首批批量内容。
        let maxLookahead = recognitionLookahead
        var cursor = buffer.captureStart

        while active,
              self.generation == generation,
              self.recognitionSessionID == recognitionSessionID,
              !Task.isCancelled {
            guard let recognizer else { return }

            // 短暂落后继续处理，只有超过阈值才重同步到当前播放位置。
            if cursor < playbackTime - Self.maximumRecognitionLag {
                let oldCursor = cursor
                let resyncTarget = max(playbackTime, buffer.captureStart)
                cursor = resyncTarget
                transcript.clearPreview()
                skippedWindowCount += 1
                totalSkippedSeconds += cursor - oldCursor
                Log.app.debug("跳过落后识别窗口：\(String(format: "%.1f", oldCursor))s → \(String(format: "%.1f", cursor))s（累计跳过 \(skippedWindowCount) 次 / \(String(format: "%.1f", totalSkippedSeconds))s）")
            }

            // 限制识别进度：只识别播放位置前方 maxLookahead 秒内的音频，
            // 避免本地视频无限向后识别导致长视频 UI 卡死。
            if cursor > playbackTime + maxLookahead {
                let now = Date().timeIntervalSince1970
                if now - lastAheadWaitLog >= 3 {
                    lastAheadWaitLog = now
                    Log.app.debug("识别已超前播放位置 \(String(format: "%.1f", maxLookahead))s，等待播放追上（cursor=\(String(format: "%.1f", cursor))s）")
                }
                handleRecognitionStall()
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }

            let availableEnd = min(
                buffer.capturedEnd,
                cursor + speechWindowPlanner.configuration.maximumWindowDuration
            )
            guard let availableSamples = buffer.extract(from: cursor, to: availableEnd) else {
                // 音频尚未缓冲到目标窗口：节流记录，便于确认识别等待的是音频还是模型。
                logBufferWaitIfNeeded(windowStart: cursor)
                handleRecognitionStall()
                try? await Task.sleep(for: .milliseconds(120))
                continue
            }

            let window: SpeechWindowPlanner.Window
            switch speechWindowPlanner.nextWindow(
                samples: availableSamples,
                sampleRate: buffer.sampleRateValue,
                startTime: cursor
            ) {
            case .waitForMoreAudio:
                logBufferWaitIfNeeded(windowStart: cursor)
                handleRecognitionStall()
                try? await Task.sleep(for: .milliseconds(120))
                continue

            case .skipSilence(let nextCursor):
                if nextCursor > cursor {
                    cursor = nextCursor
                } else {
                    try? await Task.sleep(for: .milliseconds(120))
                }
                continue

            case .transcribe(let nextWindow):
                window = nextWindow
            }

            guard let samples = buffer.extract(from: window.startTime, to: window.endTime),
                  !samples.isEmpty
            else {
                try? await Task.sleep(for: .milliseconds(120))
                continue
            }

            let windowStart = window.startTime
            let windowDuration = window.duration

            setStatus(state: .transcribing)
            do {
                let outcome = try await recognizer.transcribe(
                    samples: samples,
                    sampleRate: buffer.sampleRateValue,
                    windowStart: windowStart,
                    windowDuration: windowDuration,
                    language: effectiveRecognitionLanguage,
                    emitPartial: true,
                    recognitionSessionID: recognitionSessionID
                )
                guard self.generation == generation,
                      self.recognitionSessionID == recognitionSessionID
                else { return }
                if let language = outcome.language, !language.isEmpty {
                    currentLanguage = language
                }
                transcribedWindowCount += 1
                setStatus(state: outcome.segmentCount > 0 ? .ready : .listening)
                // 识别成功，推进到下一个窗口
                cursor = window.endTime
                lastRecognitionProgressTime = Date()
                didNotifyStalledForGeneration = false
            } catch is CancellationError {
                // 真正的取消：循环任务被 stopLoops / 换片 / seek 取消，
                // 或 generation 已变化（新会话接管），此时才应退出。
                if Task.isCancelled || self.generation != generation || !self.active {
                    return
                }
                // 其余 CancellationError 视作临时不可用：重试当前窗口，不推进 cursor
                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                // 单个窗口失败（含模型尚未就绪）：重试当前窗口，不推进 cursor
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

    /// 本地可预读来源在识别停滞时，把已识别的 pending 立即 flush 出去，
    /// 避免短视频（不足首批窗口）永远凑不满导致等待门控死锁。
    private func handleRecognitionStall() {
        guard sourceCanPreload, !initialBatchCompleted, !didNotifyStalledForGeneration,
              let last = lastRecognitionProgressTime,
              Date().timeIntervalSince(last) >= 3 else { return }
        didNotifyStalledForGeneration = true
        batchCoordinator?.flushPendingNow()
    }

    /// 音频缓冲等待日志（节流：状态变化或每 3 秒一次，避免刷屏）。
    private var lastBufferWaitLog: TimeInterval = -.infinity

    private func logBufferWaitIfNeeded(windowStart: TimeInterval) {
        let now = Date().timeIntervalSince1970
        guard now - lastBufferWaitLog >= 3 else { return }
        lastBufferWaitLog = now
        Log.app.debug("等待音频缓冲：目标窗口 \(String(format: "%.1f", windowStart))s，已捕获到 \(String(format: "%.1f", self.buffer.capturedEnd))s")
    }
}

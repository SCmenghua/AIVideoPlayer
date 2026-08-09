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
    private let recognizerFactory: @MainActor () -> any SpeechRecognizer
    private let playerSourceFactory: @MainActor (any PlaybackEngine) -> any AudioPipeline
    private let readerSourceFactory: @MainActor (MediaItem) -> any AudioPipeline

    private var recognizer: (any SpeechRecognizer)?
    private var source: (any AudioPipeline)?
    private var engine: (any PlaybackEngine)?
    private let buffer = PCMBuffer()
    private var generation = 0
    private var active = false
    private var modelLoaded = false
    private var currentLanguage: String?
    private var playbackTime: TimeInterval = 0
    private var loopTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var forwardTask: Task<Void, Never>?

    private let statusContinuation: AsyncStream<AISubtitleStatus>.Continuation
    private let segmentsContinuation: AsyncStream<SubtitleSegment>.Continuation

    /// 是否已启用。
    public var isActive: Bool {
        active
    }

    public init(
        settings: SubtitleSettings,
        recognizerFactory: @escaping @MainActor () -> any SpeechRecognizer = { WhisperKitSpeechRecognizer() },
        playerSourceFactory: @escaping @MainActor (any PlaybackEngine) -> any AudioPipeline = { PlayerAudioPipeline(engine: $0) },
        readerSourceFactory: @escaping @MainActor (MediaItem) -> any AudioPipeline = { AssetReaderAudioPipeline(item: $0) }
    ) {
        self.settings = settings
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
    }

    /// 播放开始 / seek 重建 / 恢复播放前调用：确保音频管线与识别循环就绪。
    public func preparePlayback(from time: TimeInterval) async {
        playbackTime = time
        guard active else { return }
        generation += 1
        stopLoops()
        await recognizer?.discardPendingResults()

        guard let engine else { return }
        if let source {
            await source.reset(to: time)
            try? await source.start(at: time)
            self.source = source
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
        buffer.reset(to: playbackTime)
        setStatus(state: .off)
    }

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
                self.segmentsContinuation.yield(segment)
            }
        }
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

import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitlePipelineTests {

    @Test func toggleActivatesAndRunsRealtimeRecognition() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let transcript = SubtitleTranscriptStore()
        let pipeline = makePipeline(
            source: source,
            recognizer: recognizer,
            transcript: transcript
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        #expect(pipeline.status.state == .listening)

        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 5, start: 0)

        await waitUntil { pipeline.status.state == .ready && !transcript.segments.isEmpty }
        #expect(recognizer.transcriptionCalls.count >= 1)
        // 实时路径：始终透出 partial。
        #expect(recognizer.lastCall?.emitPartial == true)
        #expect(pipeline.status.isModelLoaded)
        #expect(pipeline.status.language == "en")
        #expect(pipeline.emittedSegmentCount >= 1)
        #expect(!transcript.segments.isEmpty)
    }

    @Test func seekResetsCursorAndDiscardsPendingResults() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 2, start: 0)

        await pipeline.handleSeek(to: 30)
        #expect(recognizer.discardCount >= 1)

        await pipeline.preparePlayback(from: 30)
        emitSeconds(source, seconds: 5, start: 30)
        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        #expect(recognizer.lastCall?.windowStart == 30)
    }

    @Test func toggleOffStopsPipeline() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)

        await pipeline.toggle()
        #expect(pipeline.status.state == .off)
        #expect(source.stopCount >= 1)
        #expect(recognizer.state == .off)
    }

    @Test func staleFinalBeforePlaybackTimeIsDropped() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let transcript = SubtitleTranscriptStore()
        let pipeline = makePipeline(
            source: source,
            recognizer: recognizer,
            transcript: transcript
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 30)

        recognizer.emit(
            SubtitleSegment(
                startTime: 0,
                endTime: 1,
                originalText: "stale",
                confidence: 0.9,
                isPartial: false
            )
        )
        try? await Task.sleep(for: .milliseconds(100))
        #expect(transcript.segments.isEmpty)
    }

    @Test func partialBehindPlaybackIsStillWritten() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let transcript = SubtitleTranscriptStore()
        let pipeline = makePipeline(
            source: source,
            recognizer: recognizer,
            transcript: transcript
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 30)

        // 实时路径 partial 即使窗口起点略早于播放位置也不丢弃：
        // 避免识别稍慢时「识别已产出但播放器无字幕」。
        recognizer.emit(
            SubtitleSegment(
                startTime: 28,
                endTime: 33,
                originalText: "partial text",
                confidence: 0.5,
                isPartial: true
            )
        )
        try? await Task.sleep(for: .milliseconds(100))
        #expect(transcript.segments.count == 1)
        #expect(transcript.segments.first?.isPartial == true)
    }

    @Test func recognitionLoopSurvivesEngineNotReadyAndRecovers() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        // 模拟用户打开字幕时模型仍在加载：前两个窗口抛「引擎未就绪」，
        // 之后模型加载完成，识别必须自动恢复而不是永久停摆。
        recognizer.failuresBeforeSuccess = 2
        recognizer.failureError = WhisperRecognizerError.engineNotReady
        let transcript = SubtitleTranscriptStore()
        let pipeline = makePipeline(
            source: source,
            recognizer: recognizer,
            transcript: transcript
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 20, start: 0)

        // 等待识别恢复且字幕真正写入：transcript 由异步转发任务写入，
        // 只等转写调用数会在断言时出现竞态（偶发 CI 失败）。
        await waitUntil {
            recognizer.transcriptionCalls.count >= 2 && !transcript.segments.isEmpty
        }
        // 前两窗失败被跳过，第三窗（windowStart=10）恢复识别。
        #expect(recognizer.transcriptionCalls.first?.windowStart == 10)
        #expect(recognizer.transcriptionCalls.count >= 2)
        #expect(!transcript.segments.isEmpty)
    }

    @Test func activateMidPlaybackUsesEngineCurrentTime() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)
        await engine.seek(to: 30)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        // 播放到 30s 时才打开字幕：激活必须以引擎当前时间（30s）重建游标，
        // 而不是从陈旧记录值（0s）开始，否则识别永远追不上播放光标。
        await pipeline.toggle()
        emitSeconds(source, seconds: 5, start: 30)

        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        #expect(recognizer.lastCall?.windowStart == 30)
    }

    @Test func detectedLanguageIsPassedToNextWindow() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        recognizer.outcome = RecognitionOutcome(language: "zh", segmentCount: 1)
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 12, start: 0)

        await waitUntil { recognizer.transcriptionCalls.count >= 2 }
        // 首窗自动检测（language=nil），之后把检测结果传给后续窗口，
        // 避免中文等短音频逐窗口重复检测失败导致空结果。
        #expect(recognizer.transcriptionCalls[0].language == nil)
        #expect(recognizer.transcriptionCalls[1].language == "zh")
    }

    @Test func manualSourceLanguageIsPassedToRecognition() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let translationSettings = TranslationSettings(suiteName: uniqueSuiteName())
        translationSettings.isEnabled = false
        translationSettings.sourceLanguageCode = "ja"
        let pipeline = makePipeline(
            source: source,
            recognizer: recognizer,
            translationSettings: translationSettings
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 5, start: 0)

        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        // 手动指定源语言后，首个窗口直接使用该语言，不再等待自动检测。
        #expect(recognizer.transcriptionCalls.first?.language == "ja")
    }

    @Test func laggingWindowsAreSkippedToCatchUpWithPlayback() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        // 播放已推进到 30s（识别尚未处理任何窗口）：游标应跳过 0..30。
        pipeline.updatePlaybackPosition(30)
        emitSeconds(source, seconds: 40, start: 0)

        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        // 0..30 之间的窗口已落后于播放光标，应被跳过而不是继续逐个转写。
        #expect(recognizer.transcriptionCalls.first?.windowStart == 30)
        #expect(!recognizer.transcriptionCalls.contains { $0.windowStart == 5 })
    }

    // MARK: - 音频来源选路（Phase 8.8）

    @Test func localMediaUsesReaderSourceInsteadOfTap() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(
            MediaItem(
                title: "local",
                url: URL(fileURLWithPath: "/tmp/local.mp4"),
                kind: .video,
                source: .local
            )
        )
        let recorder = FactoryCallRecorder()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makeSourceSelectionPipeline(
            engine: engine,
            recognizer: recognizer,
            recorder: recorder
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()

        // 本地文件用 AVAssetReader 预读（解码快于实时），不挂 Tap。
        #expect(recorder.readerCalls == 1)
        #expect(recorder.tapCalls == 0)
    }

    @Test func networkMediaUsesPlayerTapInsteadOfReader() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(
            MediaItem(
                title: "web",
                url: makeTestURL("https://example.com/video.mp4"),
                kind: .video,
                source: .web
            )
        )
        let recorder = FactoryCallRecorder()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makeSourceSelectionPipeline(
            engine: engine,
            recognizer: recognizer,
            recorder: recorder
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()

        // 网络媒体绝不能用第二个 AVAssetReader 与 AVPlayer 抢同一 URL，
        // 必须走实时 Tap，否则播放器约 2 秒后停摆。
        #expect(recorder.readerCalls == 0)
        #expect(recorder.tapCalls == 1)
    }

    @Test func hlsMediaSkipsAudioCaptureWithoutBreakingPlayback() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(
            MediaItem(
                title: "hls",
                url: makeTestURL("https://example.com/stream.m3u8"),
                kind: .video,
                source: .web
            )
        )
        let recorder = FactoryCallRecorder()
        let recognizer = MockSpeechRecognizer()
        let pipeline = makeSourceSelectionPipeline(
            engine: engine,
            recognizer: recognizer,
            recorder: recorder
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()

        // HLS 不支持 MTAudioProcessingTap：挂 audioMix 反而会破坏播放，
        // 因此两个来源都不创建，管线保持激活但状态提示不可用。
        #expect(recorder.readerCalls == 0)
        #expect(recorder.tapCalls == 0)
        #expect(pipeline.status.state == .error)
        #expect(pipeline.isActive)
    }

    // MARK: - 辅助

    private func makeSourceSelectionPipeline(
        engine: any PlaybackEngine,
        recognizer: MockSpeechRecognizer,
        recorder: FactoryCallRecorder
    ) -> SubtitlePipeline {
        let readerSource = MockAudioPipeline()
        let tapSource = MockAudioPipeline()
        return SubtitlePipeline(
            transcript: SubtitleTranscriptStore(),
            translationSettings: makeDisabledSettings(),
            recognizerFactory: { recognizer },
            playerSourceFactory: { _ in
                recorder.recordTap()
                return tapSource
            },
            readerSourceFactory: { _ in
                recorder.recordReader()
                return readerSource
            }
        )
    }

    private func makeDisabledSettings() -> TranslationSettings {
        let settings = TranslationSettings(suiteName: uniqueSuiteName())
        settings.isEnabled = false
        return settings
    }

    private func makeTestURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("无法构造测试 URL：\(string)")
        }
        return url
    }

    private func makePipeline(
        source: MockAudioPipeline,
        recognizer: MockSpeechRecognizer,
        transcript: SubtitleTranscriptStore = SubtitleTranscriptStore(),
        translationSettings: TranslationSettings? = nil
    ) -> SubtitlePipeline {
        let settings: TranslationSettings
        if let translationSettings {
            settings = translationSettings
        } else {
            // 识别链路测试保持翻译关闭，避免真实 Fast NMT 在 CI 上被调用。
            let defaults = TranslationSettings(suiteName: uniqueSuiteName())
            defaults.isEnabled = false
            settings = defaults
        }
        return SubtitlePipeline(
            transcript: transcript,
            translationSettings: settings,
            recognizerFactory: { recognizer },
            playerSourceFactory: { _ in source },
            readerSourceFactory: { _ in source }
        )
    }

    private func emitSeconds(_ source: MockAudioPipeline, seconds: Int, start: TimeInterval) {
        for index in 0..<seconds {
            source.emit(
                PCMChunk(
                    samples: [Float](repeating: 0, count: 16_000),
                    sampleRate: 16_000,
                    startTime: start + Double(index)
                )
            )
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func uniqueSuiteName() -> String {
        "subtitle-pipeline.\(UUID().uuidString)"
    }
}

// MARK: - 测试替身

@MainActor
private final class MockAudioPipeline: AudioPipeline {
    let sourceKind: AudioSourceKind = .player
    let chunks: AsyncStream<PCMChunk>

    private let continuation: AsyncStream<PCMChunk>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0

    init() {
        let pair = AsyncStream<PCMChunk>.makeStream()
        self.chunks = pair.stream
        self.continuation = pair.continuation
    }

    func start(at playbackTime: TimeInterval) async throws {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func reset(to playbackTime: TimeInterval) async {
        resetCount += 1
    }

    func emit(_ chunk: PCMChunk) {
        continuation.yield(chunk)
    }
}

/// 记录 reader / tap 工厂调用次数（@MainActor 工厂闭包内自增）。
private final class FactoryCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _readerCalls = 0
    private var _tapCalls = 0

    var readerCalls: Int {
        lock.withLock { _readerCalls }
    }

    var tapCalls: Int {
        lock.withLock { _tapCalls }
    }

    func recordReader() {
        lock.withLock { _readerCalls += 1 }
    }

    func recordTap() {
        lock.withLock { _tapCalls += 1 }
    }
}

@MainActor
private final class MockSpeechRecognizer: SpeechRecognizer {
    private(set) var state: AIState = .off
    let segments: AsyncStream<SubtitleSegment>

    private let continuation: AsyncStream<SubtitleSegment>.Continuation
    private(set) var transcriptionCalls: [TranscriptionCall] = []
    private(set) var discardCount = 0
    var outcome = RecognitionOutcome(language: "en", segmentCount: 1)
    /// 前 N 次转写直接抛错（模拟模型加载未完成），之后恢复正常。
    var failuresBeforeSuccess = 0
    var failureError: Error = WhisperRecognizerError.engineNotReady

    struct TranscriptionCall {
        let windowStart: TimeInterval
        let language: String?
        let emitPartial: Bool
    }

    var lastCall: TranscriptionCall? {
        transcriptionCalls.last
    }

    init() {
        let pair = AsyncStream<SubtitleSegment>.makeStream()
        self.segments = pair.stream
        self.continuation = pair.continuation
    }

    func start() async throws {
        state = .listening
    }

    func stop() async {
        state = .off
    }

    func cancel() async {
        state = .off
    }

    func discardPendingResults() async {
        discardCount += 1
    }

    func emit(_ segment: SubtitleSegment) {
        continuation.yield(segment)
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        language: String?,
        emitPartial: Bool
    ) async throws -> RecognitionOutcome {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw failureError
        }
        transcriptionCalls.append(
            TranscriptionCall(windowStart: windowStart, language: language, emitPartial: emitPartial)
        )
        if outcome.segmentCount > 0 {
            continuation.yield(
                SubtitleSegment(
                    startTime: windowStart,
                    endTime: windowStart + windowDuration,
                    originalText: "hello",
                    confidence: 0.9,
                    isPartial: false
                )
            )
        }
        return outcome
    }
}

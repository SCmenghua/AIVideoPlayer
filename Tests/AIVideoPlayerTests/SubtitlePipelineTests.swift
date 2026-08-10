import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitlePipelineTests {

    @Test func toggleActivatesAndRunsLeadAheadRecognition() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        #expect(pipeline.status.state == .listening)

        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 5, start: 0)

        await waitUntil { pipeline.status.state == .ready }
        #expect(recognizer.transcriptionCalls.count >= 1)
        #expect(recognizer.lastCall?.emitPartial == false)
        #expect(pipeline.status.isModelLoaded)
        #expect(pipeline.status.language == "en")
    }

    @Test func disabledLeadAheadUsesRawPartialPath() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let settings = SubtitleSettings(suiteName: uniqueSuiteName())
        settings.isLeadAheadEnabled = false
        let source = MockAudioPipeline(canReadAhead: true)
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(
            source: source,
            recognizer: recognizer,
            settings: settings
        )
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 5, start: 0)

        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        #expect(recognizer.lastCall?.emitPartial == true)
    }

    @Test func seekResetsCursorAndDiscardsPendingResults() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
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

    @Test func settingsChangeRebuildsCursor() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 2, start: 0)

        await pipeline.rebuildAfterSettingsChange()
        #expect(recognizer.discardCount >= 1)

        emitSeconds(source, seconds: 5, start: 0)
        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        #expect(recognizer.lastCall?.emitPartial == false)
    }

    @Test func toggleOffStopsPipeline() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
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

    @Test func staleSegmentsBeforePlaybackTimeAreDropped() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 30)

        let collect = Task { () -> SubtitleSegment? in
            for await segment in pipeline.segments {
                if Task.isCancelled { return nil }
                return segment
            }
            return nil
        }
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
        collect.cancel()
        #expect(await collect.value == nil)
    }

    @Test func micSourceAlwaysUsesRawPath() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: false)
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 5, start: 0)

        await waitUntil { recognizer.transcriptionCalls.count >= 1 }
        #expect(recognizer.lastCall?.emitPartial == true)
        #expect(pipeline.shouldUseLeadAhead == false)
    }

    @Test func recognitionLoopSurvivesEngineNotReadyAndRecovers() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
        let recognizer = MockSpeechRecognizer()
        // 模拟用户打开字幕时模型仍在加载：前两个窗口抛「引擎未就绪」，
        // 之后模型加载完成，识别必须自动恢复而不是永久停摆。
        recognizer.failuresBeforeSuccess = 2
        recognizer.failureError = WhisperRecognizerError.engineNotReady
        let pipeline = makePipeline(source: source, recognizer: recognizer)
        pipeline.attach(playbackEngine: engine)

        let collect = Task { () -> [SubtitleSegment] in
            var segments: [SubtitleSegment] = []
            for await segment in pipeline.segments {
                segments.append(segment)
                if segments.count >= 2 { return segments }
            }
            return segments
        }

        await pipeline.toggle()
        await pipeline.preparePlayback(from: 0)
        emitSeconds(source, seconds: 20, start: 0)

        await waitUntil { recognizer.transcriptionCalls.count >= 2 }
        // 前两窗失败被跳过，第三窗（windowStart=10）恢复识别。
        #expect(recognizer.transcriptionCalls.first?.windowStart == 10)
        #expect(recognizer.transcriptionCalls.count >= 2)

        collect.cancel()
        let segments = await collect.value
        #expect(!segments.isEmpty)
    }

    @Test func activateMidPlaybackUsesEngineCurrentTime() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)
        await engine.seek(to: 30)

        let source = MockAudioPipeline(canReadAhead: true)
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

        let source = MockAudioPipeline(canReadAhead: true)
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

    @Test func laggingWindowsAreSkippedToCatchUpWithPlayback() async throws {
        let engine = MockPlaybackEngine()
        try await engine.load(MockRemoteFiles.sampleMediaItem)

        let source = MockAudioPipeline(canReadAhead: true)
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

    // MARK: - 辅助

    private func makePipeline(
        source: MockAudioPipeline,
        recognizer: MockSpeechRecognizer,
        settings: SubtitleSettings? = nil
    ) -> SubtitlePipeline {
        SubtitlePipeline(
            settings: settings ?? SubtitleSettings(suiteName: uniqueSuiteName()),
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
    let canReadAhead: Bool
    let chunks: AsyncStream<PCMChunk>

    private let continuation: AsyncStream<PCMChunk>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0

    init(canReadAhead: Bool) {
        self.canReadAhead = canReadAhead
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

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

    struct TranscriptionCall {
        let windowStart: TimeInterval
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

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        emitPartial: Bool
    ) async throws -> RecognitionOutcome {
        transcriptionCalls.append(
            TranscriptionCall(windowStart: windowStart, emitPartial: emitPartial)
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

import Foundation
import Testing
@testable import AIVideoPlayer

/// 验证核心协议可由具体实现替换（Mock 即为未来真实实现的模板）。
@MainActor
struct ProtocolConformanceTests {

    @Test func mediaExtractorReturnsMediaItems() async throws {
        let extractor = MockMediaExtractor()
        let url = try #require(URL(string: "https://example.com/page"))

        let items = try await extractor.extractMedia(from: url)

        #expect(items.count == 1)
        #expect(items[0].kind == .video)
        #expect(items[0].source == .web)
    }

    @Test func remoteFileBrowserReturnsMockContents() async throws {
        let browser = MockRemoteFileBrowser()

        let files = try await browser.listRemoteFiles()

        #expect(files.count == MockRemoteFiles.contents.count)
        #expect(!files.isEmpty)
    }

    @Test func playbackEngineLoadsItem() async throws {
        let engine = MockPlaybackEngine()
        let item = MockRemoteFiles.sampleMediaItem

        try await engine.load(item)

        #expect(engine.state == .ready(item))
        #expect(engine.currentItem == item)
    }

    @Test func speechRecognizerEmitsPartialSegments() async {
        let recognizer = MockSpeechRecognizer()
        let segment = SubtitleSegment(
            startTime: 0,
            endTime: 1,
            originalText: "hello",
            confidence: 0.9,
            isPartial: true
        )

        recognizer.emit(segment)

        var received: [SubtitleSegment] = []
        for await value in recognizer.segments {
            received.append(value)
            if received.count == 1 { break }
        }

        #expect(received == [segment])
    }

    @Test func translationEngineIsReplaceable() async throws {
        let engine = MockTranslationEngine()

        let result = try await engine.translate("Hello", from: "en", to: "zh")

        #expect(result == "translated:Hello")
    }

    @Test func subtitleEngineManagesTimeline() async {
        let engine = MockSubtitleEngine()
        let segment = SubtitleSegment(
            startTime: 0,
            endTime: 1,
            originalText: "hi",
            confidence: 0.8
        )

        await engine.append(segment)

        #expect(engine.segments.count == 1)
        #expect(engine.segment(at: 0.5) == segment)
        #expect(engine.segment(at: 1.5) == nil)

        await engine.removeAll()
        #expect(engine.segments.isEmpty)
    }

    @Test func subtitleStatusProviderTransitionsToReady() async {
        let provider = MockSubtitleStatusProvider()

        await provider.toggle()
        #expect(provider.status.state == .loading)

        var seen: Set<AIState> = []
        for await status in provider.statusStream {
            seen.insert(status.state)
            if status.state == .ready { break }
        }

        #expect(seen.contains(.loading))
        #expect(seen.contains(.listening))
        #expect(seen.contains(.ready))
    }

    @Test func subtitleStatusProviderToggleOffStopsTransition() async {
        let provider = MockSubtitleStatusProvider()

        await provider.toggle()
        #expect(provider.status.state == .loading)

        try? await Task.sleep(for: .seconds(0.4))
        await provider.toggle()
        #expect(provider.status.state == .off)

        // 等待超过原定进入 .listening 的时长，确认流转已被取消。
        try? await Task.sleep(for: .seconds(1.3))
        #expect(provider.status.state == .off)
    }
}

// MARK: - 测试替身

private struct MockMediaExtractor: MediaExtractor {
    func extractMedia(from url: URL) async throws -> [MediaItem] {
        [MediaItem(title: "Sample", url: url, kind: .video, source: .web)]
    }
}

@MainActor
private final class MockPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentItem: MediaItem?

    func load(_ item: MediaItem) async throws {
        currentItem = item
        state = .ready(item)
    }

    func play() async {
        if case .ready(let item) = state {
            state = .playing(item)
        }
    }

    func pause() async {
        if case .playing(let item) = state {
            state = .paused(item)
        }
    }

    func seek(to time: TimeInterval) async {}
    func setRate(_ rate: Float) async {}
    func setVolume(_ volume: Float) async {}
}

@MainActor
private final class MockSpeechRecognizer: SpeechRecognizer {
    private(set) var state: AIState = .off
    let segments: AsyncStream<SubtitleSegment>
    private let continuation: AsyncStream<SubtitleSegment>.Continuation

    init() {
        let pair = AsyncStream<SubtitleSegment>.makeStream()
        segments = pair.stream
        continuation = pair.continuation
    }

    func start() async throws {
        state = .listening
    }

    func stop() async {
        state = .off
    }

    func cancel() async {
        continuation.finish()
        state = .off
    }

    func emit(_ segment: SubtitleSegment) {
        continuation.yield(segment)
    }
}

@MainActor
private final class MockTranslationEngine: TranslationEngine {
    func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String
    ) async throws -> String {
        "translated:\(text)"
    }
}

@MainActor
private final class MockSubtitleEngine: SubtitleEngine {
    private(set) var segments: [SubtitleSegment] = []

    func append(_ segment: SubtitleSegment) async {
        segments.append(segment)
    }

    func update(_ segment: SubtitleSegment) async {
        if let index = segments.firstIndex(where: { $0.id == segment.id }) {
            segments[index] = segment
        }
    }

    func removeAll() async {
        segments.removeAll()
    }

    func segment(at time: TimeInterval) -> SubtitleSegment? {
        segments.first { $0.startTime <= time && time < $0.endTime }
    }
}

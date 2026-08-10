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

    @Test func remoteFileBrowserConnectsAndListsDirectory() async throws {
        let browser = MockRemoteFileBrowser()
        let profile = RemoteServerProfile(
            name: "NAS",
            rootURL: try #require(URL(string: "https://nas.example.local/dav/")),
            username: "user"
        )
        let credentials = RemoteCredentials(username: "user", password: "pass")

        try await browser.connect(to: profile, credentials: credentials)
        let files = try await browser.listDirectory(at: profile.rootURL)

        #expect(files.count == MockRemoteFiles.contents.count)
        #expect(!files.isEmpty)

        await browser.disconnect()
    }

    @Test func playbackEngineLoadsItem() async throws {
        let engine = MockPlaybackEngine()
        let item = MockRemoteFiles.sampleMediaItem

        try await engine.load(item)

        #expect(engine.state == .ready)
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

        let result = try await engine.translate("Hello", from: "en", to: "zh", context: nil)

        #expect(result == "translated:Hello")
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

    func discardPendingResults() async {}

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        language: String?,
        emitPartial: Bool
    ) async throws -> RecognitionOutcome {
        RecognitionOutcome(language: nil, segmentCount: 0)
    }

    func emit(_ segment: SubtitleSegment) {
        continuation.yield(segment)
    }
}

@MainActor
private final class MockTranslationEngine: TranslationEngine {
    var providerID: TranslationProviderID { .fastNMT }
    var displayName: String { "Mock" }
    var isFullyLocal: Bool { true }
    var supportsContextPolish: Bool { false }
    var isReady: Bool { true }

    func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String,
        context: TranslationContext?
    ) async throws -> String {
        "translated:\(text)"
    }
}

import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitlePipelineTranslationTests {

    @Test func finalSegmentIsTranslatedAndYielded() async throws {
        let settings = makeTranslationSettings(enabled: true)
        let recognizer = MockSpeechRecognizer()
        let translator = MockTranslator(translated: "你好")
        let pipeline = makePipeline(
            translationSettings: settings,
            recognizer: recognizer,
            translator: translator
        )

        let collect = Task {
            await pipeline.toggle()
            recognizer.emit(
                SubtitleSegment(
                    startTime: 0,
                    endTime: 1,
                    originalText: "Hello",
                    confidence: 0.9,
                    isPartial: false
                )
            )
            return await firstSegment(from: pipeline)
        }

        let segment = await collect.value
        #expect(segment?.originalText == "Hello")
        #expect(segment?.translatedText == "你好")
        #expect(translator.callCount == 1)
        #expect(translator.lastSource == nil)
    }

    @Test func partialSegmentsPassThroughUntranslated() async throws {
        let settings = makeTranslationSettings(enabled: true)
        let recognizer = MockSpeechRecognizer()
        let translator = MockTranslator()
        let pipeline = makePipeline(
            translationSettings: settings,
            recognizer: recognizer,
            translator: translator
        )

        let collect = Task {
            await pipeline.toggle()
            recognizer.emit(
                SubtitleSegment(
                    startTime: 0,
                    endTime: 1,
                    originalText: "Hel",
                    confidence: 0.5,
                    isPartial: true
                )
            )
            return await firstSegment(from: pipeline)
        }

        let segment = await collect.value
        #expect(segment?.translatedText == nil)
        #expect(translator.callCount == 0)
    }

    @Test func disabledTranslationPassesThrough() async throws {
        let settings = makeTranslationSettings(enabled: false)
        let recognizer = MockSpeechRecognizer()
        let translator = MockTranslator()
        let pipeline = makePipeline(
            translationSettings: settings,
            recognizer: recognizer,
            translator: translator
        )

        let collect = Task {
            await pipeline.toggle()
            recognizer.emit(
                SubtitleSegment(
                    startTime: 0,
                    endTime: 1,
                    originalText: "Hello",
                    confidence: 0.9,
                    isPartial: false
                )
            )
            return await firstSegment(from: pipeline)
        }

        let segment = await collect.value
        #expect(segment?.translatedText == nil)
        #expect(translator.callCount == 0)
    }

    @Test func translationFailurePassesThroughOriginal() async throws {
        let settings = makeTranslationSettings(enabled: true)
        let recognizer = MockSpeechRecognizer()
        let translator = MockTranslator()
        translator.error = FastNMTError.languagePackNotInstalled
        let pipeline = makePipeline(
            translationSettings: settings,
            recognizer: recognizer,
            translator: translator
        )

        let collect = Task {
            await pipeline.toggle()
            recognizer.emit(
                SubtitleSegment(
                    startTime: 0,
                    endTime: 1,
                    originalText: "Hello",
                    confidence: 0.9,
                    isPartial: false
                )
            )
            return await firstSegment(from: pipeline)
        }

        let segment = await collect.value
        #expect(segment?.translatedText == nil)
        #expect(translator.callCount == 1)
    }

    @Test func contextPolishSuppliesContextAfterFirstTranslation() async throws {
        let settings = makeTranslationSettings(enabled: true)
        settings.isContextPolishEnabled = true
        let recognizer = MockSpeechRecognizer()
        let translator = MockTranslator()
        translator.supportsContextPolish = true
        let pipeline = makePipeline(
            translationSettings: settings,
            recognizer: recognizer,
            translator: translator
        )

        await pipeline.toggle()
        recognizer.emit(
            SubtitleSegment(
                startTime: 0, endTime: 1, originalText: "First",
                confidence: 0.9, isPartial: false
            )
        )
        let first = await firstSegment(from: pipeline)
        #expect(first?.translatedText == "译文")
        // 首句翻译时还没有历史上下文，context 应为 nil。
        #expect(translator.lastContext == nil)

        recognizer.emit(
            SubtitleSegment(
                startTime: 1, endTime: 2, originalText: "Second",
                confidence: 0.9, isPartial: false
            )
        )
        let second = await firstSegment(from: pipeline)
        #expect(second?.translatedText == "译文")
        #expect(translator.lastContext?.isEmpty == false)
        #expect(translator.lastContext?.text.contains("First") == true)
    }

    @Test func statusTransitionsThroughTranslating() async throws {
        let settings = makeTranslationSettings(enabled: true)
        let recognizer = MockSpeechRecognizer()
        let pipeline = makePipeline(
            translationSettings: settings,
            recognizer: recognizer,
            translator: MockTranslator()
        )

        let statusTask = Task {
            for await status in pipeline.statusStream {
                if status.state == .translating {
                    return true
                }
            }
            return false
        }

        await pipeline.toggle()
        recognizer.emit(
            SubtitleSegment(
                startTime: 0, endTime: 1, originalText: "Hello",
                confidence: 0.9, isPartial: false
            )
        )

        let sawTranslating = await statusTask.value
        #expect(sawTranslating)
    }

    // MARK: - 辅助

    private func makeTranslationSettings(enabled: Bool) -> TranslationSettings {
        let settings = TranslationSettings(suiteName: uniqueSuiteName())
        settings.isEnabled = enabled
        settings.selectedProviderID = .fastNMT
        return settings
    }

    private func makePipeline(
        translationSettings: TranslationSettings,
        recognizer: MockSpeechRecognizer,
        translator: MockTranslator
    ) -> SubtitlePipeline {
        SubtitlePipeline(
            settings: SubtitleSettings(suiteName: uniqueSuiteName()),
            translationSettings: translationSettings,
            translationProviderFactory: { _ in translator },
            recognizerFactory: { recognizer }
        )
    }

    private func firstSegment(from pipeline: SubtitlePipeline) async -> SubtitleSegment? {
        for await segment in pipeline.segments {
            return segment
        }
        return nil
    }

    private func uniqueSuiteName() -> String {
        "pipeline-translation.\(UUID().uuidString)"
    }
}

// MARK: - 测试替身

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
        state = .off
    }

    func discardPendingResults() async {}

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        emitPartial: Bool
    ) async throws -> RecognitionOutcome {
        RecognitionOutcome(language: nil, segmentCount: 0)
    }

    func emit(_ segment: SubtitleSegment) {
        continuation.yield(segment)
    }
}

@MainActor
private final class MockTranslator: TranslationEngine {
    let translated: String
    var error: Error?
    var supportsContextPolish = false
    private(set) var callCount = 0
    private(set) var lastContext: TranslationContext?
    private(set) var lastSource: String?

    init(translated: String = "译文") {
        self.translated = translated
    }

    var providerID: TranslationProviderID { .fastNMT }
    var displayName: String { "Mock" }
    var isFullyLocal: Bool { true }
    var isReady: Bool { true }

    func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String,
        context: TranslationContext?
    ) async throws -> String {
        callCount += 1
        lastContext = context
        lastSource = sourceLanguage
        if let error {
            throw error
        }
        return translated
    }
}

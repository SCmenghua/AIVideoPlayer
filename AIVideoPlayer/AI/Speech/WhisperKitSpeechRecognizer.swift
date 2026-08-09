import Foundation
import WhisperKit

/// Whisper 模型内置错误。
public enum WhisperModelError: LocalizedError, Sendable {
    case modelBundleMissing(String)

    public var errorDescription: String? {
        switch self {
        case .modelBundleMissing(let name):
            "未找到内置 Whisper 模型资源（\(name)）。请运行 scripts/fetch-whisper-model.sh 后重新构建。"
        }
    }
}

/// WhisperKit 本地实时识别实现（Phase 5）。
/// 模型随 App 内置（Resources/Models/whisperkit-coreml），音频不离开设备；
/// 通过 `transcribe` 处理领先窗口 / 实时窗口，并把 Whisper 的 partial / final
/// 映射为 `SubtitleSegment` 写入 `segments` 流。
@MainActor
public final class WhisperKitSpeechRecognizer: SpeechRecognizer {
    public private(set) var state: AIState = .off
    public let segments: AsyncStream<SubtitleSegment>

    private let continuation: AsyncStream<SubtitleSegment>.Continuation
    private let modelFolderName: String
    private let modelFolderSubdirectory: String?
    private var whisperKit: WhisperKit?
    private var generation: Int = 0

    public init(
        modelFolderName: String = "whisperkit-coreml",
        modelFolderSubdirectory: String? = "Models"
    ) {
        self.modelFolderName = modelFolderName
        self.modelFolderSubdirectory = modelFolderSubdirectory
        let pair = AsyncStream<SubtitleSegment>.makeStream()
        self.segments = pair.stream
        self.continuation = pair.continuation
    }

    // MARK: - SpeechRecognizer

    public func start() async throws {
        guard whisperKit == nil else { return }
        state = .loading
        do {
            let folder = try Self.bundledModelFolder(
                name: modelFolderName,
                subdirectory: modelFolderSubdirectory
            )
            let kit = try await WhisperKit(
                modelFolder: folder.path,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            whisperKit = kit
            state = .listening
        } catch {
            state = .error
            throw error
        }
    }

    public func stop() async {
        generation += 1
        whisperKit = nil
        state = .off
    }

    public func cancel() async {
        generation += 1
        whisperKit = nil
        state = .off
    }

    public func discardPendingResults() async {
        generation += 1
    }

    public func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        emitPartial: Bool
    ) async throws -> RecognitionOutcome {
        try Task.checkCancellation()
        guard let whisperKit else {
            throw CancellationError()
        }

        let resampled = try AudioResampler.resample(
            samples,
            from: sampleRate,
            to: AudioResampler.whisperSampleRate
        )
        guard !resampled.isEmpty else {
            return RecognitionOutcome(language: nil, segmentCount: 0)
        }

        let options = DecodingOptions(
            task: .transcribe,
            temperature: 0.0,
            usePrefillPrompt: false,
            detectLanguage: true,
            skipSpecialTokens: true,
            wordTimestamps: false,
            suppressBlank: true,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: 1,
            chunkingStrategy: nil
        )

        // 原始路径：透出 Whisper 的 streaming partial。
        // 注意：TranscriptionCallback 是 @Sendable，只捕获 Sendable 值。
        let continuation = self.continuation
        let callback: TranscriptionCallback? = emitPartial
            ? { progress in
                let text = Self.cleanedText(progress.text)
                guard !text.isEmpty else { return nil }
                continuation.yield(
                    SubtitleSegment(
                        startTime: windowStart,
                        endTime: windowStart + windowDuration,
                        originalText: text,
                        confidence: Self.confidence(from: progress.avgLogprob),
                        isPartial: true
                    )
                )
                return nil
            }
            : nil

        let results = try await whisperKit.transcribe(
            audioArray: resampled,
            decodeOptions: options,
            callback: callback
        )

        try Task.checkCancellation()
        var segmentCount = 0
        var language: String?
        for result in results {
            if !result.language.isEmpty {
                language = result.language
            }
            for segment in result.segments {
                let text = Self.cleanedText(segment.text)
                guard !text.isEmpty else { continue }
                continuation.yield(
                    SubtitleSegment(
                        startTime: windowStart + Double(segment.start),
                        endTime: windowStart + Double(segment.end),
                        originalText: text,
                        confidence: Self.confidence(from: segment.avgLogprob),
                        isPartial: false
                    )
                )
                segmentCount += 1
            }
        }
        return RecognitionOutcome(language: language, segmentCount: segmentCount)
    }

    // MARK: - 工具

    static func bundledModelFolder(name: String, subdirectory: String?) throws -> URL {
        let url = subdirectory.map {
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: $0)
        } ?? Bundle.main.url(forResource: name, withExtension: nil)
        guard let url else {
            throw WhisperModelError.modelBundleMissing(name)
        }
        return url
    }

    private static func cleanedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<\|[^>]*\|>"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func confidence(from avgLogprob: Float?) -> Double {
        guard let avgLogprob else { return 0 }
        return min(max(1.0 + Double(avgLogprob), 0.0), 1.0)
    }
}

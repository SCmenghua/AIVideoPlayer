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

/// 识别引擎运行期错误。
public enum WhisperRecognizerError: LocalizedError, Sendable {
    /// 模型仍在加载 / 尚未就绪时收到了转写请求。
    /// 注意：这不是取消，调用方应稍后重试而不是结束识别循环。
    case engineNotReady

    public var errorDescription: String? {
        switch self {
        case .engineNotReady:
            "识别引擎尚未就绪"
        }
    }
}

/// WhisperKit 本地实时识别实现（Phase 5）。
/// 模型随 App 内置（Resources/Models/whisperkit-coreml），音频不离开设备；
/// 通过 `transcribe` 处理由语音停顿切分的窗口，并把 Whisper 的 partial / final
/// 映射为 `SubtitleSegment` 写入 `segments` 流。
@MainActor
public final class WhisperKitSpeechRecognizer: SpeechRecognizer {
    public private(set) var state: AIState = .off
    public let segments: AsyncStream<SubtitleSegment>

    private let continuation: AsyncStream<SubtitleSegment>.Continuation
    private let modelFolderName: String
    private let modelFolderSubdirectory: String?
    private var whisperKit: WhisperKit?
    /// 转写窗口世代计数器：discard / stop / cancel 时递增。
    /// 用锁保护的盒子（而非 MainActor 存储属性）是为了让 WhisperKit 的
    /// @Sendable streaming 回调（音频线程）也能读取当前世代。
    private let generationBox = GenerationBox()

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
            Log.app.info("加载内置 Whisper 模型：\(folder.path)")
            let loadStart = ContinuousClock.now
            let kit = try await WhisperKit(
                modelFolder: folder.path,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            let elapsed = loadStart.duration(to: .now)
            Log.app.info("Whisper 模型加载成功（\(elapsed.formatted(.units(allowed: [.seconds])))）")
            whisperKit = kit
            state = .listening
        } catch {
            Log.app.error("Whisper 模型加载失败：\(error.localizedDescription)")
            state = .error
            throw error
        }
    }

    public func stop() async {
        generationBox.increment()
        whisperKit = nil
        state = .off
    }

    public func cancel() async {
        generationBox.increment()
        whisperKit = nil
        state = .off
    }

    public func discardPendingResults() async {
        generationBox.increment()
    }

    public func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        language: String?,
        emitPartial: Bool,
        recognitionSessionID: Int
    ) async throws -> RecognitionOutcome {
        try Task.checkCancellation()
        let windowGeneration = generationBox.current()
        guard let whisperKit else {
            // 模型加载仍在进行：抛普通错误而非 CancellationError，
            // 让上层识别循环跳过本次尝试并继续重试（而不是被当作取消而退出）。
            throw WhisperRecognizerError.engineNotReady
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
            language: language,
            temperature: 0.0,
            // 标准解码路径：检测（或传入）语言后预填 SOT + 语言 + 任务 + 时间戳 token。
            // 此前关闭 prefill 会让多语言模型缺少语言提示，中文解码不稳定。
            usePrefillPrompt: true,
            detectLanguage: true,
            skipSpecialTokens: true,
            wordTimestamps: false,
            suppressBlank: true,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: 1,
            chunkingStrategy: nil
        )

        let windowStarted = Date()

        // 实时路径：透出 Whisper 的 streaming partial。
        // 注意：TranscriptionCallback 是 @Sendable，只捕获 Sendable 值。
        let continuation = self.continuation
        let generationBox = self.generationBox
        let callback: TranscriptionCallback?
        if emitPartial {
            callback = { progress in
                // seek / 停止后仍在途的 partial 直接丢弃。
                guard generationBox.current() == windowGeneration else { return nil }
                let text = Self.cleanedText(progress.text)
                guard !text.isEmpty else { return nil }
                continuation.yield(
                    SubtitleSegment(
                        startTime: windowStart,
                        endTime: windowStart + windowDuration,
                        originalText: text,
                        confidence: Self.confidence(from: progress.avgLogprob),
                        isPartial: true,
                        recognitionSessionID: recognitionSessionID
                    )
                )
                return nil
            }
        } else {
            callback = nil
        }

        let results = try await whisperKit.transcribe(
            audioArray: resampled,
            decodeOptions: options,
            callback: callback
        )

        try Task.checkCancellation()
        // seek / 停止发生在转写期间时，丢弃本次窗口的 final 结果。
        guard generationBox.current() == windowGeneration else {
            return RecognitionOutcome(language: nil, segmentCount: 0)
        }
        var segmentCount = 0
        var detectedLanguage = language
        for result in results {
            if !result.language.isEmpty {
                detectedLanguage = result.language
            }
            for segment in result.segments {
                let text = Self.cleanedText(segment.text)
                guard !text.isEmpty else { continue }
                // 防御：时间戳异常（end <= start / 为 0）时收敛为最小可显示时长，
                // 避免「翻译已产出但字幕不显示」（零时长片段永远无法命中播放光标）。
                let start = windowStart + Double(segment.start)
                let end = max(
                    windowStart + Double(segment.end),
                    start + SubtitleSegment.minimumDisplayDuration
                )
                continuation.yield(
                    SubtitleSegment(
                        startTime: start,
                        endTime: end,
                        originalText: text,
                        confidence: Self.confidence(from: segment.avgLogprob),
                        isPartial: false,
                        recognitionSessionID: recognitionSessionID
                    )
                )
                segmentCount += 1
            }
        }
        let windowElapsedMs = Int(Date().timeIntervalSince(windowStarted) * 1000)
        Log.app.debug("识别窗口完成 window=\(String(format: "%.1f", windowStart))s 耗时=\(windowElapsedMs)ms samples=\(samples.count) language=\(detectedLanguage ?? "nil") segments=\(segmentCount)")
        return RecognitionOutcome(language: detectedLanguage, segmentCount: segmentCount)
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

    nonisolated private static func cleanedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<\|[^>]*\|>"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated private static func confidence(from avgLogprob: Float?) -> Double {
        guard let avgLogprob else { return 0 }
        return min(max(1.0 + Double(avgLogprob), 0.0), 1.0)
    }
}

/// 线程安全的世代计数器（音频回调线程写入/读取）。
private final class GenerationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func current() -> Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

import Foundation

/// 一次窗口转写的汇总结果。
public struct RecognitionOutcome: Sendable {
    public let language: String?
    public let segmentCount: Int

    public init(language: String?, segmentCount: Int) {
        self.language = language
        self.segmentCount = segmentCount
    }
}

/// 本地语音识别（Phase 5 使用 WhisperKit）。音频不离开设备。
/// 通过 AsyncStream 持续产出 partial / final SubtitleSegment。
@MainActor
public protocol SpeechRecognizer: AnyObject {
    var state: AIState { get }
    var segments: AsyncStream<SubtitleSegment> { get }

    func start() async throws
    func stop() async
    func cancel() async
    /// 丢弃进行中的结果（seek / 模式切换时调用，避免旧结果覆盖新窗口）。
    func discardPendingResults() async
    /// 转写一段 PCM（实现负责重采样到 16kHz），并把结果写入 `segments` 流。
    /// `emitPartial` 开启时额外透出 streaming partial（原始实时路径）。
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        emitPartial: Bool
    ) async throws -> RecognitionOutcome
}

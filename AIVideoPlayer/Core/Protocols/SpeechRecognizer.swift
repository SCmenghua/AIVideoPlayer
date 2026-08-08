import Foundation

/// 本地语音识别（Phase 5 使用 WhisperKit）。音频不离开设备。
/// 通过 AsyncStream 持续产出 partial / final SubtitleSegment。
@MainActor
public protocol SpeechRecognizer: AnyObject {
    var state: AIState { get }
    var segments: AsyncStream<SubtitleSegment> { get }

    func start() async throws
    func stop() async
    func cancel() async
}

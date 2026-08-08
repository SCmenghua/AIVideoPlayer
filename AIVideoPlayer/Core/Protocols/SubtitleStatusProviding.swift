import Foundation

/// AI 字幕状态来源（开/关、模型加载、聆听/转写/翻译进度）。
/// Phase 1 使用 MockSubtitleStatusProvider，Phase 5 由 WhisperKit 管线实现。
/// 状态变化通过 statusStream 推送；toggle 可随时取消进行中的流转。
@MainActor
public protocol SubtitleStatusProviding: AnyObject {
    var status: AISubtitleStatus { get }
    var statusStream: AsyncStream<AISubtitleStatus> { get }
    func toggle() async
}

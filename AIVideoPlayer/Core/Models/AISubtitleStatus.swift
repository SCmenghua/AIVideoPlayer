import Foundation

/// AI 字幕子系统的状态快照，首页据此渲染。
public struct AISubtitleStatus: Equatable, Sendable {
    public let state: AIState
    public let isModelLoaded: Bool
    public let language: String?

    public init(state: AIState, isModelLoaded: Bool, language: String?) {
        self.state = state
        self.isModelLoaded = isModelLoaded
        self.language = language
    }
}

import Foundation

/// AI 字幕流水线的 UI 级状态（Phase 5 起由真实管线驱动）。
public enum AIState: String, Codable, Sendable, CaseIterable {
    case off
    case loading
    case listening
    case transcribing
    case translating
    case ready
    case error
}

import Foundation

/// PlaybackEngine 暴露的高层播放状态。
/// 当前媒体条目由 `PlaybackEngine.currentItem` 单独跟踪，不在状态中重复携带。
public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case ended
    case failed(String)
}

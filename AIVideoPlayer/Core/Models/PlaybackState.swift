import Foundation

/// PlaybackEngine 暴露的高层播放状态（Phase 3 实现）。
public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading(MediaItem)
    case ready(MediaItem)
    case playing(MediaItem)
    case paused(MediaItem)
    case ended(MediaItem)
    case failed(String)
}

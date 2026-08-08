import Foundation

/// 播放进度快照（由 AVPlayer 周期时间回调产出）。
public struct PlaybackProgress: Equatable, Sendable {
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let rate: Float

    public init(currentTime: TimeInterval, duration: TimeInterval, rate: Float) {
        self.currentTime = currentTime
        self.duration = duration
        self.rate = rate
    }

    /// 归一化进度 0...1。
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}

import AVFoundation
import Foundation

/// 封装 AVPlayer 生命周期。View 禁止直接接触 AVPlayer，
/// 必须经由 ViewModel → PlaybackEngine。
/// `player` 是唯一的渲染例外：仅供 UI 绑定 AVPlayerLayer，不做任何播放控制。
@MainActor
public protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    var currentItem: MediaItem? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var rate: Float { get }

    /// 渲染句柄（只读）：仅供 VideoLayerView 绑定 AVPlayerLayer。
    var player: AVPlayer? { get }

    /// 播放状态变化流（idle / loading / ready / playing / paused / ended / failed）。
    var stateStream: AsyncStream<PlaybackState> { get }
    /// 播放进度流（周期时间回调驱动，约 0.5s 一次）。
    var progressStream: AsyncStream<PlaybackProgress> { get }

    func load(_ item: MediaItem) async throws
    func play() async
    func pause() async
    func seek(to time: TimeInterval) async
    func setRate(_ rate: Float) async
    func setVolume(_ volume: Float) async
}

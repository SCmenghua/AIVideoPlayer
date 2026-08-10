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
    /// 当前媒体是否为横屏视频（宽 > 高）；未知/失败时返回 false。
    var isLandscapeVideo: Bool { get }
    /// 横竖屏检测是否已有结论（false 表示仍在检测中或检测失败）。
    var isResolutionKnown: Bool { get }

    /// 渲染句柄（只读）：仅供 VideoLayerView 绑定 AVPlayerLayer；
    /// Phase 5 起亦供 PlayerAudioPipeline 读取音频输出（Service 层，非播放控制）。
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
    /// 重新检测并等待横竖屏结果（全屏入口使用；未知时最多等待 timeout 秒）。
    func resolveVideoOrientation(timeout: TimeInterval) async -> Bool
}

/// 默认按竖屏处理，测试替身无需重复实现。
extension PlaybackEngine {
    public var isLandscapeVideo: Bool { false }
    public var isResolutionKnown: Bool { true }
    public func resolveVideoOrientation(timeout: TimeInterval = 2) async -> Bool {
        isLandscapeVideo
    }
}

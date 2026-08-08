import Foundation

/// 封装 AVPlayer 生命周期。View 禁止直接接触 AVPlayer，
/// 必须经由 ViewModel → PlaybackEngine。Phase 3 落地 AVPlayerPlaybackEngine。
@MainActor
public protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    var currentItem: MediaItem? { get }

    func load(_ item: MediaItem) async throws
    func play() async
    func pause() async
    func seek(to time: TimeInterval) async
    func setRate(_ rate: Float) async
    func setVolume(_ volume: Float) async
}

import AVFoundation
import Foundation
import Observation

/// 播放器状态：注入 PlaybackEngine，消费状态/进度流，持有全屏、字幕、比例等 UI 状态。
@MainActor
@Observable
final class PlayerViewModel {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var currentItem: MediaItem?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    private(set) var volume: Float = 1

    var isFullScreen = false
    var isSubtitleEnabled = false
    var aspectMode: VideoAspectMode = .fit
    var isControlsVisible = true
    var isScrubbing = false
    var seekTarget: TimeInterval = 0

    private let engine: any PlaybackEngine
    private var stateTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    init(engine: any PlaybackEngine = AVPlayerPlaybackEngine()) {
        self.engine = engine
    }

    var isPlaying: Bool { playbackState == .playing }

    var currentProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    /// 渲染句柄（架构红线唯一例外：仅供 VideoLayerView 绑定 AVPlayerLayer）。
    var player: AVPlayer? { engine.player }

    // MARK: - 观察

    func startObserving() {
        stopObserving()

        let stateStream = engine.stateStream
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in stateStream {
                self.playbackState = state
            }
        }

        let progressStream = engine.progressStream
        progressTask = Task { [weak self] in
            guard let self else { return }
            for await progress in progressStream {
                self.currentTime = progress.currentTime
                self.duration = progress.duration
                self.rate = progress.rate
            }
        }
    }

    func stopObserving() {
        stateTask?.cancel()
        progressTask?.cancel()
        stateTask = nil
        progressTask = nil
    }

    // MARK: - 播放控制

    func load(_ item: MediaItem) async {
        currentItem = item
        playbackState = .loading
        do {
            try await engine.load(item)
        } catch {
            playbackState = .failed(error.localizedDescription)
        }
    }

    func togglePlayPause() async {
        if playbackState == .ended {
            await engine.seek(to: 0)
            await engine.play()
        } else if isPlaying {
            await engine.pause()
        } else {
            await engine.play()
        }
    }

    func seek(to time: TimeInterval) async {
        await engine.seek(to: time)
    }

    func setRate(_ newRate: Float) async {
        rate = newRate
        await engine.setRate(newRate)
    }

    func setVolume(_ newVolume: Float) async {
        volume = newVolume
        await engine.setVolume(newVolume)
    }

    func toggleSubtitle() {
        // Phase 6 接入 SubtitleOverlay 渲染；本期仅提供控制位。
        isSubtitleEnabled.toggle()
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
    }
}

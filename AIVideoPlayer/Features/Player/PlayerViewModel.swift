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
    var videoScale: Double = 1.0
    var isControlsVisible = true
    var isScrubbing = false
    var seekTarget: TimeInterval = 0

    private let engine: any PlaybackEngine
    private var subtitlePipeline: SubtitlePipeline?
    private var stateTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    /// 当前加载任务：新加载会取消旧任务，避免并发加载互相覆盖状态。
    private var loadTask: Task<Void, Never>?
    /// 加载世代：旧任务完成时若世代不匹配则丢弃结果，防止过期加载
    /// 覆盖新媒体的状态（换片后旧任务超时把状态打成 failed 等）。
    private var loadGeneration = 0

    init(
        engine: any PlaybackEngine = AVPlayerPlaybackEngine(),
        subtitlePipeline: SubtitlePipeline? = nil
    ) {
        self.engine = engine
        self.subtitlePipeline = subtitlePipeline
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
                if state == .ended {
                    self.subtitlePipeline?.handlePlaybackEnded()
                }
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

    /// 加载新媒体：先复位播放器（进度 / 状态 / 字幕循环），再异步加载。
    /// 换片时旧加载任务会被取消，且旧任务的结果不会覆盖新状态（generation 守卫）。
    func load(_ item: MediaItem) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadTask = nil

        // 换片复位：清空旧视频的进度与状态，避免残留旧进度条 / 转圈。
        playbackState = .loading
        currentItem = item
        currentTime = 0
        duration = 0
        isScrubbing = false
        seekTarget = 0
        subtitlePipeline?.handlePlaybackEnded()

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.load(item)
                guard generation == self.loadGeneration else { return }
                self.playbackState = .ready
            } catch is CancellationError {
                // 已被更新的加载取代：保留新加载的状态，不覆盖。
            } catch {
                guard generation == self.loadGeneration else { return }
                self.playbackState = .failed(error.localizedDescription)
            }
        }
    }

    /// 手动初始化：重新加载当前媒体（清理卡住的转圈 / 状态异常，恢复播放）。
    func reinitialize() {
        guard let item = currentItem else { return }
        load(item)
    }

    /// 注入共享 AI 字幕管线（PlayerView 从 AppEnvironment 获取）。
    func attachSubtitlePipeline(_ pipeline: SubtitlePipeline) {
        subtitlePipeline = pipeline
        pipeline.attach(playbackEngine: engine)
    }

    func togglePlayPause() async {
        if playbackState == .ended {
            await engine.seek(to: 0)
            await play()
        } else if isPlaying {
            await engine.pause()
            subtitlePipeline?.handlePlaybackPaused()
        } else {
            await play()
        }
    }

    func seek(to time: TimeInterval) async {
        await engine.seek(to: time)
        await subtitlePipeline?.handleSeek(to: time)
        if isPlaying {
            await prepareAIForPlayback(from: time)
        }
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
        // Phase 6：控制位驱动 SubtitleOverlay 显示。
        isSubtitleEnabled.toggle()
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
    }

    // MARK: - AI 超前识别

    private func play() async {
        await prepareAIForPlayback(from: currentTime)
        await engine.play()
    }

    /// 播放前准备音频管线：重建/启动来源，超前模式下先等 Δ 秒预读完成再出声。
    private func prepareAIForPlayback(from time: TimeInterval) async {
        guard let subtitlePipeline else { return }
        await subtitlePipeline.preparePlayback(from: time)
        guard subtitlePipeline.shouldUseLeadAhead else { return }
        _ = await subtitlePipeline.waitUntilLeadCaptured(
            delta: subtitlePipeline.leadAheadWindow,
            timeout: 4
        )
    }
}

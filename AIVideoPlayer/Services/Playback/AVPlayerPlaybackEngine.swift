import AVFoundation
import Foundation

/// AVPlayer 封装（Phase 3）。
/// 所有状态在主线程维护；状态/进度通过 AsyncStream 推送给 ViewModel。
/// 取消调用方 Task 即取消 load 等待。
@MainActor
public final class AVPlayerPlaybackEngine: PlaybackEngine {
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentItem: MediaItem?
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var rate: Float = 1
    public private(set) var isLandscapeVideo = false
    public private(set) var isResolutionKnown = false

    public var player: AVPlayer? { avPlayer }
    public let stateStream: AsyncStream<PlaybackState>
    public let progressStream: AsyncStream<PlaybackProgress>

    private let avPlayer: AVPlayer
    private let stateContinuation: AsyncStream<PlaybackState>.Continuation
    private let progressContinuation: AsyncStream<PlaybackProgress>.Continuation

    /// 
onisolated(unsafe)：仅 MainActor 方法与 deinit 访问（deinit 无隔离，
    /// 无法读取 actor 隔离的非 Sendable 存储属性；属性本身只在本类内使用，
    /// 且 deinit 时对象不再被并发访问，安全）。
    nonisolated(unsafe) private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    /// 进度/状态兜底节拍器：周期读取 AVPlayer 当前时间并推送进度，
    /// 即使周期观察者回调未送达也能驱动 UI 时间与进度条。
    nonisolated(unsafe) private var tickerTask: Task<Void, Never>?
    /// 分辨率检测任务：换片时取消旧检测，避免旧结果覆盖新媒体。
    nonisolated(unsafe) private var resolutionTask: Task<Void, Never>?
    /// 上次报告的时间，用于减少频繁的 UI 更新
    private var lastReportedTime: TimeInterval = 0
    /// 是否正在等待缓冲恢复播放
    private var isWaitingForBuffer = false

    deinit {
        tickerTask?.cancel()
        resolutionTask?.cancel()
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    public init() {
        let statePair = AsyncStream<PlaybackState>.makeStream()
        stateStream = statePair.stream
        stateContinuation = statePair.continuation

        let progressPair = AsyncStream<PlaybackProgress>.makeStream()
        progressStream = progressPair.stream
        progressContinuation = progressPair.continuation

        avPlayer = AVPlayer()
        addObservers()
        startTicker()
    }

    public func load(_ item: MediaItem) async throws {
        // 换片初始化：先暂停旧播放，避免新条目因 rate 保持 1 而自动播放，
        // 导致状态机被「加载完成 → ready」覆盖成错误状态（播放按钮错乱）。
        avPlayer.pause()
        let playerItem = AVPlayerItem(url: item.url)
        avPlayer.replaceCurrentItem(with: playerItem)
        currentItem = item
        // 换片复位：清空旧媒体的进度/倍速，避免 UI 显示残留。
        currentTime = 0
        duration = 0
        rate = 1
        isLandscapeVideo = false
        isResolutionKnown = false
        isWaitingForBuffer = false
        setState(.loading)
        detectResolution(for: item, asset: playerItem.asset)
        do {
            try await waitUntilReady(playerItem)
        } catch is CancellationError {
            // 换片 / 取消：本加载已失效，状态由新加载负责，不打 failed。
            throw CancellationError()
        } catch {
            // 引擎状态同步标记失败，避免停留在 loading 让 UI 无法恢复。
            setState(.failed(error.localizedDescription))
            throw error
        }
        // 加载完成后立即推送一次进度（0s + 已知时长），让进度条范围尽快就绪。
        emitProgress(at: 0)
        // 防御：加载完成时若已处于播放态（异常自动播放），保持播放态。
        if avPlayer.timeControlStatus == .playing {
            setState(.playing)
        } else {
            setState(.ready)
        }
    }

    public func play() async {
        // 失败态只能走重试（重新加载），不允许直接播放。
        if case .failed = state { return }
        avPlayer.play()
        // 立即同步状态：即使 timeControlStatus KVO 回调未送达，
        // 播放按钮也能马上切到暂停态。
        setState(.playing)
    }

    public func pause() async {
        avPlayer.pause()
        // 立即同步状态：即使 KVO 回调未送达，播放按钮也能马上切回播放态。
        // 播放结束态保留给 replay 逻辑（从 0 重播），不让 pause 覆盖。
        if state != .ended {
            setState(.paused)
        }
    }

    public func seek(to time: TimeInterval) async {
        // 已知时长时把目标收敛到 [0, duration]，避免进度条拖动越界。
        let duration = currentItemDuration
        let clamped = duration > 0 ? min(max(time, 0), duration) : max(time, 0)
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        await avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        emitProgress(at: clamped)
    }

    public func setRate(_ newRate: Float) async {
        rate = newRate
        avPlayer.defaultRate = newRate
        if avPlayer.timeControlStatus == .playing {
            avPlayer.rate = newRate
        }
    }

    /// 重新检测并等待横竖屏结果（全屏入口使用）。
    /// 检测失败 / 超时按竖屏处理，返回当前结论。
    public func resolveVideoOrientation(timeout: TimeInterval = 2) async -> Bool {
        guard let item = currentItem,
              let asset = avPlayer.currentItem?.asset else {
            return isLandscapeVideo
        }
        detectResolution(for: item, asset: asset)
        let deadline = ContinuousClock.now + .seconds(timeout)
        while !isResolutionKnown, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return isLandscapeVideo
    }

    // MARK: - Private

    /// 检测当前视频横竖屏（宽 > 高为横屏）。异步进行，不阻塞加载完成。
    /// 使用播放器已加载的 asset（而非拿 URL 重新创建），远程 / HLS 也能识别。
    private func detectResolution(for item: MediaItem, asset: AVAsset) {
        resolutionTask?.cancel()
        isResolutionKnown = false
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled,
                  let tracks = try? await asset.loadTracks(withMediaType: .video),
                  let track = tracks.first else {
                self.markResolutionKnown(for: item)
                return
            }
            let size = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            guard !Task.isCancelled, self.currentItem?.id == item.id else { return }
            // 用 preferredTransform 修正旋转元数据：手机竖拍视频的编码尺寸可能是
            // 横向的，按展示方向判断才是真实横竖屏。
            let displayRect = CGRect(origin: .zero, size: size).applying(transform)
            self.isLandscapeVideo = abs(displayRect.width) > abs(displayRect.height)
            self.isResolutionKnown = true
        }
    }

    private func markResolutionKnown(for item: MediaItem) {
        guard !Task.isCancelled, currentItem?.id == item.id else { return }
        isResolutionKnown = true
    }

    /// 进度/状态兜底节拍器：每 0.5s 读取一次 AVPlayer 当前时间/时长/状态并推送。
    /// 与 KVO / 周期观察者双通道并存：
    /// 1) 周期观察者回调异常未送达时，时间与进度仍能驱动 UI；
    /// 2) timeControlStatus KVO 未送达时，状态也能在下一拍收敛。
    /// 
    /// BUG FIX: 将 ticker 从每 0.5s 的同步 currentTime() 调用改为使用周期观察者的缓存值，
    /// 减少主线程阻塞，避免长视频 UI 卡顿崩溃。
    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                // 不再直接调用 avPlayer.currentTime()，而是使用周期观察者更新的 currentTime
                // 只有在时间变化超过阈值时才更新 UI，减少不必要的刷新
                let duration = self.currentItemDuration
                if abs(self.currentTime - self.lastReportedTime) > 0.1 || duration != self.duration {
                    self.lastReportedTime = self.currentTime
                    self.progressContinuation.yield(
                        PlaybackProgress(currentTime: self.currentTime, duration: duration, rate: self.avPlayer.rate)
                    )
                }
                self.handleTimeControlStatus(self.avPlayer.timeControlStatus)
            }
        }
    }

    private func addObservers() {
        // 播放/暂停状态（KVO 回调在主线程，Swift 6 下显式回到 MainActor）。
        statusObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.handleTimeControlStatus(status)
            }
        }

        // 周期进度回调（主队列）。
        // BUG FIX: 使用周期观察者更新内部 currentTime，而不是在 ticker 中同步调用
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self else { return }
                // 更新内部缓存的时间，供 ticker 使用
                self.currentTime = seconds.isFinite ? seconds : 0
                self.emitProgress(at: self.currentTime)
            }
        }

        // 播放结束通知（主队列）。
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 非隔离上下文只可提及 Sendable 的标识，避免把 Notification 传入 MainActor。
            let endedItemID = (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            Task { @MainActor in
                guard let self,
                      let endedItemID,
                      let current = self.avPlayer.currentItem,
                      ObjectIdentifier(current) == endedItemID else {
                    return
                }
                self.setState(.ended)
            }
        }
    }

    /// BUG FIX: 处理网络视频缓冲问题
    /// 当 AVPlayer 进入 waitingToPlayAtSpecifiedRate 状态时，需要监听 isPlaybackLikelyToKeepUp
    /// 属性，当缓冲就绪时自动恢复播放
    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isWaitingForBuffer = false
            setState(.playing)
        case .paused:
            if state == .playing && !isWaitingForBuffer {
                setState(.paused)
            }
        case .waitingToPlayAtSpecifiedRate:
            // 网络视频缓冲：检查是否因为缓冲不足而暂停
            if state == .playing {
                guard let item = avPlayer.currentItem else { return }
                // 检查缓冲状态
                if item.isPlaybackLikelyToKeepUp {
                    // 缓冲已就绪，自动恢复播放
                    avPlayer.play()
                    isWaitingForBuffer = false
                } else {
                    // 仍在缓冲，标记状态但不改变 UI 显示（避免闪烁）
                    isWaitingForBuffer = true
                    // 开始监听缓冲就绪
                    observeBufferStatus(for: item)
                }
            }
        @unknown default:
            break
        }
    }

    /// 监听网络视频的缓冲状态，当缓冲就绪时自动恢复播放
    private func observeBufferStatus(for item: AVPlayerItem) {
        // 使用 KVO 监听 isPlaybackLikelyToKeepUp
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 最多等待 10 秒
            let maxAttempts = 20
            var attempts = 0
            while self.isWaitingForBuffer && attempts < maxAttempts {
                try? await Task.sleep(for: .milliseconds(500))
                attempts += 1
                
                guard self.avPlayer.currentItem === item,
                      self.state == .playing,
                      self.isWaitingForBuffer else {
                    break
                }
                
                if item.isPlaybackLikelyToKeepUp {
                    // 缓冲就绪，恢复播放
                    self.avPlayer.play()
                    self.isWaitingForBuffer = false
                    break
                }
            }
        }
    }

    private func emitProgress(at seconds: TimeInterval) {
        // 无媒体 / 时间不可用时回退 0，避免 NaN 污染 UI（进度条/时间标签）。
        let safeSeconds = seconds.isFinite ? seconds : 0
        currentTime = safeSeconds
        duration = currentItemDuration
        rate = avPlayer.rate
        progressContinuation.yield(
            PlaybackProgress(currentTime: safeSeconds, duration: currentItemDuration, rate: avPlayer.rate)
        )
    }

    private var currentItemDuration: TimeInterval {
        guard let item = avPlayer.currentItem else {
            return 0
        }
        // CMTime.seconds 是非可选 Double；不可用 if let 解包。
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            return seconds
        }
        // HLS / 渐进式媒体：duration 未就绪时用可 seek 范围末端近似，
        // 保证进度条显示与拖动范围正确（否则范围退化成 0...1，拖动即从头播）。
        if let range = item.seekableTimeRanges.last?.timeRangeValue,
           range.end.seconds.isFinite,
           range.end.seconds > 0 {
            return range.end.seconds
        }
        return 0
    }

    private func waitUntilReady(_ item: AVPlayerItem) async throws {
        // 加载超时兜底：网络不可达 / 媒体不可用且状态不前进时，
        // 避免 load 永久卡在 loading。
        let deadline = ContinuousClock.now + .seconds(60)
        while true {
            try Task.checkCancellation()
            // 加载期间当前条目被替换（新的加载已开始）：本加载已失效。
            guard avPlayer.currentItem === item else {
                throw CancellationError()
            }
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                throw PlaybackEngineError.loadFailed(item.error?.localizedDescription ?? "媒体加载失败")
            case .unknown:
                if ContinuousClock.now >= deadline {
                    throw PlaybackEngineError.loadFailed("媒体加载超时")
                }
                try await Task.sleep(for: .milliseconds(50))
            @unknown default:
                throw PlaybackEngineError.loadFailed("未知加载状态")
            }
        }
    }

    private func setState(_ newState: PlaybackState) {
        guard state != newState else { return }
        // 状态机不变量：播放中不允许被 ready 回退（换片加载完成的竞态防护）。
        if state == .playing, newState == .ready { return }
        state = newState
        stateContinuation.yield(newState)
    }
}

/// 播放引擎错误。
public enum PlaybackEngineError: LocalizedError, Sendable {
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            message
        }
    }
}

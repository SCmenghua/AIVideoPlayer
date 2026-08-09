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

    public var player: AVPlayer? { avPlayer }
    public let stateStream: AsyncStream<PlaybackState>
    public let progressStream: AsyncStream<PlaybackProgress>

    private let avPlayer: AVPlayer
    private let stateContinuation: AsyncStream<PlaybackState>.Continuation
    private let progressContinuation: AsyncStream<PlaybackProgress>.Continuation

    /// `nonisolated(unsafe)`：仅 MainActor 方法与 deinit 访问（deinit 无隔离，
    /// 无法读取 actor 隔离的非 Sendable 存储属性；属性本身只在本类内使用，
    /// 且 deinit 时对象不再被并发访问，安全）。
    nonisolated(unsafe) private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?

    deinit {
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
    }

    public func load(_ item: MediaItem) async throws {
        let playerItem = AVPlayerItem(url: item.url)
        avPlayer.replaceCurrentItem(with: playerItem)
        currentItem = item
        // 换片复位：清空旧媒体的进度/倍速，避免 UI 显示残留。
        currentTime = 0
        duration = 0
        rate = 1
        setState(.loading)
        try await waitUntilReady(playerItem)
        setState(.ready)
    }

    public func play() async {
        avPlayer.play()
    }

    public func pause() async {
        avPlayer.pause()
    }

    public func seek(to time: TimeInterval) async {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        await avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        emitProgress(at: time)
    }

    public func setRate(_ newRate: Float) async {
        rate = newRate
        avPlayer.defaultRate = newRate
        if avPlayer.timeControlStatus == .playing {
            avPlayer.rate = newRate
        }
    }

    public func setVolume(_ newVolume: Float) async {
        avPlayer.volume = newVolume
    }

    // MARK: - Private

    private func addObservers() {
        // 播放/暂停状态（KVO 回调在主线程，Swift 6 下显式回到 MainActor）。
        statusObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.handleTimeControlStatus(status)
            }
        }

        // 周期进度回调（主队列）。
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                self?.emitProgress(at: seconds)
            }
        }

        // 播放结束通知（主队列）。
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 非隔离上下文只提取 Sendable 的标识，避免把 Notification 传入 MainActor。
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

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            setState(.playing)
        case .paused:
            if state == .playing {
                setState(.paused)
            }
        case .waitingToPlayAtSpecifiedRate:
            // 缓冲中：保持当前状态，避免 UI 抖动。
            break
        @unknown default:
            break
        }
    }

    private func emitProgress(at seconds: TimeInterval) {
        currentTime = seconds
        duration = currentItemDuration
        rate = avPlayer.rate
        progressContinuation.yield(
            PlaybackProgress(currentTime: seconds, duration: currentItemDuration, rate: avPlayer.rate)
        )
    }

    private var currentItemDuration: TimeInterval {
        guard let seconds = avPlayer.currentItem?.duration.seconds,
              seconds.isFinite,
              seconds > 0 else {
            return 0
        }
        return seconds
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

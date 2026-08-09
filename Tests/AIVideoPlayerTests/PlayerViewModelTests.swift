import AVFoundation
import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct PlayerViewModelTests {

    @Test func loadSetsCurrentItemAndReadyState() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        #expect(viewModel.currentItem == MockRemoteFiles.sampleMediaItem)
        #expect(viewModel.playbackState == .ready)
    }

    @Test func togglePlayPauseSwitchesStates() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        await viewModel.togglePlayPause()
        await waitUntil { viewModel.playbackState == .playing }
        #expect(viewModel.isPlaying)

        await viewModel.togglePlayPause()
        await waitUntil { viewModel.playbackState == .paused }
        #expect(!viewModel.isPlaying)
    }

    @Test func progressStreamUpdatesTimeAndDuration() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        engine.emitProgress(PlaybackProgress(currentTime: 30, duration: 120, rate: 1))
        await waitUntil { viewModel.currentTime == 30 }

        #expect(viewModel.duration == 120)
        #expect(viewModel.currentProgress > 0.2)
    }

    @Test func seekForwardsToEngine() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)

        await viewModel.seek(to: 42)

        #expect(engine.currentTime == 42)
    }

    @Test func fullscreenSubtitleAspectToggles() {
        let viewModel = PlayerViewModel(engine: MockPlaybackEngine())

        viewModel.isFullScreen = true
        #expect(viewModel.isFullScreen)

        viewModel.toggleSubtitle()
        #expect(viewModel.isSubtitleEnabled)

        viewModel.setAspectMode(.fill)
        #expect(viewModel.aspectMode == .fill)

        viewModel.videoScale = 1.5
        #expect(viewModel.videoScale == 1.5)
    }

    @Test func progressModelNormalizes() {
        let progress = PlaybackProgress(currentTime: 60, duration: 120, rate: 1)
        #expect(progress.progress == 0.5)
    }

    // MARK: - Phase 7.6 换片复位与手动初始化

    @Test func loadResetsProgressBeforeEngineReady() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        // 先模拟第一条视频播放到一半。
        engine.emitProgress(PlaybackProgress(currentTime: 60, duration: 120, rate: 1))
        await waitUntil { viewModel.currentTime == 60 }

        viewModel.load(MockRemoteFiles.sampleMediaItem)

        // 换片立即复位：不残留旧进度，进入 loading 态。
        #expect(viewModel.currentTime == 0)
        #expect(viewModel.duration == 0)
        #expect(viewModel.playbackState == .loading)
        #expect(viewModel.currentItem == MockRemoteFiles.sampleMediaItem)

        await waitUntil { viewModel.playbackState == .ready }
    }

    @Test func reinitializeReloadsCurrentItem() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }
        #expect(engine.loadCount == 1)

        viewModel.reinitialize()
        await waitUntil { engine.loadCount == 2 }
        await waitUntil { viewModel.playbackState == .ready }
        #expect(viewModel.currentItem == MockRemoteFiles.sampleMediaItem)
    }

    @Test func secondLoadSupersedesFirstWithoutClobberingState() async throws {
        let engine = GatedPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        // 第一条加载停在闸门上。
        await waitUntil { engine.pendingLoadCount == 1 }

        let secondItem = MediaItem(
            title: "Second",
            url: try #require(URL(string: "https://example.com/second.mp4")),
            kind: .video,
            source: .web
        )
        viewModel.load(secondItem)
        await waitUntil { viewModel.playbackState == .ready }
        #expect(viewModel.currentItem == secondItem)

        // 放行第一条加载：它的结果不得覆盖第二条的状态。
        engine.releaseFirstLoad()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.playbackState == .ready)
        #expect(viewModel.currentItem == secondItem)
    }

    @Test func loadDoesNotClobberPlayingState() async throws {
        let engine = AutoplayPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        // 模拟换片后新条目自动开始播放（引擎只发 .playing，不发 .ready）。
        viewModel.load(MockRemoteFiles.sampleMediaItem)

        await waitUntil { viewModel.playbackState == .playing }
        // 加载任务完成后不应把播放态打回 ready（播放按钮错乱回归）。
        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.playbackState == .playing)
        #expect(viewModel.currentItem == MockRemoteFiles.sampleMediaItem)
    }

    // MARK: - Phase 7.8 流未送达兜底

    @Test func togglePlayPauseWorksEvenWhenStateStreamIsSilent() async throws {
        let engine = SilentPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        await viewModel.togglePlayPause()
        #expect(viewModel.isPlaying)

        await viewModel.togglePlayPause()
        #expect(!viewModel.isPlaying)
    }

    @Test func refreshStateAndProgressPullsFromEngine() async throws {
        let engine = SilentPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        engine.simulateProgress(currentTime: 30, duration: 120)
        viewModel.refreshStateAndProgress()

        #expect(viewModel.currentTime == 30)
        #expect(viewModel.duration == 120)
        #expect(viewModel.currentProgress > 0.2)
    }

    @Test func seekRefreshesTimeAndDurationFromEngine() async throws {
        let engine = SilentPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        await viewModel.seek(to: 42)

        #expect(engine.currentTime == 42)
        #expect(viewModel.currentTime == 42)
        #expect(viewModel.duration == 120)
    }

    @Test func failedLoadIsNotRegressedByRefresh() async throws {
        let engine = SilentPlaybackEngine()
        engine.failNextLoad = true
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil {
            if case .failed = viewModel.playbackState { return true }
            return false
        }

        viewModel.refreshStateAndProgress()

        var isFailed = false
        if case .failed = viewModel.playbackState { isFailed = true }
        #expect(isFailed)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// 可手动放行的播放引擎：第一条 load 停在闸门上，后续 load 立即完成。
@MainActor
private final class GatedPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentItem: MediaItem?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1

    var player: AVPlayer? { nil }

    let stateStream: AsyncStream<PlaybackState>
    let progressStream: AsyncStream<PlaybackProgress>
    private let stateContinuation: AsyncStream<PlaybackState>.Continuation
    private let progressContinuation: AsyncStream<PlaybackProgress>.Continuation

    private(set) var pendingLoadCount = 0
    private var firstLoadGate: CheckedContinuation<Void, Never>?

    init() {
        let statePair = AsyncStream<PlaybackState>.makeStream()
        stateStream = statePair.stream
        stateContinuation = statePair.continuation

        let progressPair = AsyncStream<PlaybackProgress>.makeStream()
        progressStream = progressPair.stream
        progressContinuation = progressPair.continuation
    }

    func load(_ item: MediaItem) async throws {
        if firstLoadGate == nil {
            pendingLoadCount += 1
            await withCheckedContinuation { continuation in
                firstLoadGate = continuation
            }
            firstLoadGate = nil
        }
        currentItem = item
        duration = 120
        state = .ready
        stateContinuation.yield(.ready)
    }

    func releaseFirstLoad() {
        firstLoadGate?.resume()
    }

    func play() async {
        state = .playing
        stateContinuation.yield(.playing)
    }

    func pause() async {
        state = .paused
        stateContinuation.yield(.paused)
    }

    func seek(to time: TimeInterval) async {
        currentTime = time
        progressContinuation.yield(PlaybackProgress(currentTime: time, duration: duration, rate: rate))
    }

    func setRate(_ newRate: Float) async {
        rate = newRate
    }

    func setVolume(_ volume: Float) async {}
}

/// 静默播放引擎：play/pause/load/seek 更新内部状态但不 yield 流，
/// 验证 ViewModel 不依赖流也能同步播放器状态与进度（设备端流丢失兜底）。
@MainActor
private final class SilentPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentItem: MediaItem?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    var failNextLoad = false

    var player: AVPlayer? { nil }

    let stateStream: AsyncStream<PlaybackState>
    let progressStream: AsyncStream<PlaybackProgress>
    private let stateContinuation: AsyncStream<PlaybackState>.Continuation
    private let progressContinuation: AsyncStream<PlaybackProgress>.Continuation

    init() {
        let statePair = AsyncStream<PlaybackState>.makeStream()
        stateStream = statePair.stream
        stateContinuation = statePair.continuation

        let progressPair = AsyncStream<PlaybackProgress>.makeStream()
        progressStream = progressPair.stream
        progressContinuation = progressPair.continuation
    }

    func load(_ item: MediaItem) async throws {
        if failNextLoad {
            state = .failed("加载失败")
            throw PlaybackEngineError.loadFailed("加载失败")
        }
        currentItem = item
        duration = 120
        state = .ready
    }

    func play() async {
        state = .playing
    }

    func pause() async {
        state = .paused
    }

    func seek(to time: TimeInterval) async {
        currentTime = time
    }

    func setRate(_ newRate: Float) async {
        rate = newRate
    }

    func setVolume(_ volume: Float) async {}

    func simulateProgress(currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
    }
}

/// 模拟换片后新条目自动播放的引擎：load 期间直接发出 .playing。
@MainActor
private final class AutoplayPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentItem: MediaItem?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1

    var player: AVPlayer? { nil }

    let stateStream: AsyncStream<PlaybackState>
    let progressStream: AsyncStream<PlaybackProgress>
    private let stateContinuation: AsyncStream<PlaybackState>.Continuation
    private let progressContinuation: AsyncStream<PlaybackProgress>.Continuation

    init() {
        let statePair = AsyncStream<PlaybackState>.makeStream()
        stateStream = statePair.stream
        stateContinuation = statePair.continuation

        let progressPair = AsyncStream<PlaybackProgress>.makeStream()
        progressStream = progressPair.stream
        progressContinuation = progressPair.continuation
    }

    func load(_ item: MediaItem) async throws {
        currentItem = item
        duration = 120
        state = .playing
        stateContinuation.yield(.playing)
    }

    func play() async {}
    func pause() async {}

    func seek(to time: TimeInterval) async {
        currentTime = time
        progressContinuation.yield(PlaybackProgress(currentTime: time, duration: duration, rate: rate))
    }

    func setRate(_ newRate: Float) async {
        rate = newRate
    }

    func setVolume(_ volume: Float) async {}
}

import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct PlayerViewModelSubtitleTests {

    @Test func playPreparesSubtitlePipeline() async throws {
        let engine = MockPlaybackEngine()
        let pipeline = SpySubtitlePipeline()
        let viewModel = PlayerViewModel(engine: engine, subtitlePipeline: pipeline)
        viewModel.attachSubtitlePipeline(pipeline)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        await viewModel.togglePlayPause()
        await waitUntil { viewModel.isPlaying }

        #expect(!pipeline.preparedTimes.isEmpty)
        #expect(pipeline.attachedEngineCount >= 1)
    }

    @Test func seekNotifiesPipeline() async throws {
        let engine = MockPlaybackEngine()
        let pipeline = SpySubtitlePipeline()
        let viewModel = PlayerViewModel(engine: engine, subtitlePipeline: pipeline)
        viewModel.attachSubtitlePipeline(pipeline)

        await viewModel.seek(to: 42)

        #expect(pipeline.seekTimes == [42])
    }

    @Test func pauseNotifiesPipeline() async throws {
        let engine = MockPlaybackEngine()
        let pipeline = SpySubtitlePipeline()
        let viewModel = PlayerViewModel(engine: engine, subtitlePipeline: pipeline)
        viewModel.attachSubtitlePipeline(pipeline)
        viewModel.startObserving()

        viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }
        await viewModel.togglePlayPause()
        await waitUntil { viewModel.isPlaying }
        await viewModel.togglePlayPause()
        // 播放状态由引擎状态流异步驱动，需等状态落定再断言。
        await waitUntil { !viewModel.isPlaying }

        #expect(pipeline.pauseCount >= 1)
        #expect(!viewModel.isPlaying)
    }

    @Test func attachingActivePipelineDefaultsSubtitlesOn() async throws {
        let pipeline = SpySubtitlePipeline()
        pipeline.activeOverride = true
        let viewModel = PlayerViewModel(engine: MockPlaybackEngine(), subtitlePipeline: pipeline)

        viewModel.attachSubtitlePipeline(pipeline)

        // 管线已在设置页 / 首页启用时，播放器默认显示字幕，
        // 不用再额外点一次播放器字幕开关。
        #expect(viewModel.isSubtitleEnabled)
    }

    @Test func turningOnPlayerSubtitleActivatesInactivePipeline() async throws {
        let pipeline = SpySubtitlePipeline()
        let viewModel = PlayerViewModel(engine: MockPlaybackEngine(), subtitlePipeline: pipeline)
        viewModel.attachSubtitlePipeline(pipeline)

        // 播放器字幕开关打开：即使管线此前未启用，也应自动激活。
        viewModel.toggleSubtitle()
        #expect(viewModel.isSubtitleEnabled)
        await waitUntil { pipeline.toggleCount >= 1 }

        // 关闭字幕只隐藏叠加层，不再触发管线开关（避免重复启停模型）。
        viewModel.toggleSubtitle()
        #expect(!viewModel.isSubtitleEnabled)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(pipeline.toggleCount == 1)
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

/// 记录 PlayerViewModel 与字幕管线交互的探针。
@MainActor
private final class SpySubtitlePipeline: SubtitlePipeline {
    private(set) var preparedTimes: [TimeInterval] = []
    private(set) var seekTimes: [TimeInterval] = []
    private(set) var pauseCount = 0
    private(set) var attachedEngineCount = 0
    private(set) var toggleCount = 0
    /// 模拟管线已激活 / 未激活状态。
    var activeOverride: Bool?
    var leadAheadEnabled = false

    init() {
        super.init(settings: SubtitleSettings(suiteName: "spy.\(UUID().uuidString)"))
    }

    override var isActive: Bool {
        activeOverride ?? super.isActive
    }

    override func toggle() async {
        toggleCount += 1
    }

    override func attach(playbackEngine: any PlaybackEngine) {
        attachedEngineCount += 1
        super.attach(playbackEngine: playbackEngine)
    }

    override func preparePlayback(from time: TimeInterval) async {
        preparedTimes.append(time)
    }

    override func handleSeek(to time: TimeInterval) async {
        seekTimes.append(time)
    }

    override func handlePlaybackPaused() {
        pauseCount += 1
    }

    override var shouldUseLeadAhead: Bool {
        leadAheadEnabled
    }

    override var leadAheadWindow: TimeInterval {
        3
    }
}

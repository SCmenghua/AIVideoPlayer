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

        await viewModel.load(MockRemoteFiles.sampleMediaItem)
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

        await viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }
        await viewModel.togglePlayPause()
        await waitUntil { viewModel.isPlaying }
        await viewModel.togglePlayPause()

        #expect(pipeline.pauseCount >= 1)
        #expect(!viewModel.isPlaying)
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
    var leadAheadEnabled = false

    init() {
        super.init(settings: SubtitleSettings(suiteName: "spy.\(UUID().uuidString)"))
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

import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct PlayerViewModelTests {

    @Test func loadSetsCurrentItemAndReadyState() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        await viewModel.load(MockRemoteFiles.sampleMediaItem)
        await waitUntil { viewModel.playbackState == .ready }

        #expect(viewModel.currentItem == MockRemoteFiles.sampleMediaItem)
        #expect(viewModel.playbackState == .ready)
    }

    @Test func togglePlayPauseSwitchesStates() async throws {
        let engine = MockPlaybackEngine()
        let viewModel = PlayerViewModel(engine: engine)
        viewModel.startObserving()

        await viewModel.load(MockRemoteFiles.sampleMediaItem)
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
    }

    @Test func progressModelNormalizes() {
        let progress = PlaybackProgress(currentTime: 60, duration: 120, rate: 1)
        #expect(progress.progress == 0.5)
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

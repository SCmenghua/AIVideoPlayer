import AVFoundation
import Foundation
@testable import AIVideoPlayer

/// 播放引擎测试替身：可手动驱动状态/进度流，验证 ViewModel 消费逻辑。
@MainActor
final class MockPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentItem: MediaItem?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    private(set) var loadCount = 0

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
        loadCount += 1
        currentItem = item
        duration = 120
        state = .ready
        stateContinuation.yield(.ready)
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

    func emitState(_ newState: PlaybackState) {
        state = newState
        stateContinuation.yield(newState)
    }

    func emitProgress(_ progress: PlaybackProgress) {
        currentTime = progress.currentTime
        duration = progress.duration
        rate = progress.rate
        progressContinuation.yield(progress)
    }
}

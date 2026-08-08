import Foundation
import Observation

/// Phase 1 占位。Phase 3 用真实 PlaybackEngine 替换 state。
@MainActor
@Observable
final class PlayerViewModel {
    enum ScreenState: Equatable, Sendable {
        case noMediaSelected
        case ready(MediaItem)
    }

    private(set) var state: ScreenState = .noMediaSelected

    func select(_ item: MediaItem) {
        state = .ready(item)
    }

    func clear() {
        state = .noMediaSelected
    }
}

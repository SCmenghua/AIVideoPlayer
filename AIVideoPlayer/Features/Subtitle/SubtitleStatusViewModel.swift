import Foundation
import Observation

/// Phase 1 的 AI 字幕状态 Mock。Phase 5 接入 WhisperKit；
/// UI 契约（AIState）与真实管线一致。所有 Task 可取消。
@MainActor
@Observable
final class SubtitleStatusViewModel {
    private(set) var status: AISubtitleStatus

    private let provider: any SubtitleStatusProviding
    private var toggleTask: Task<Void, Never>?

    init(provider: any SubtitleStatusProviding = MockSubtitleStatusProvider()) {
        self.provider = provider
        self.status = provider.status
    }

    var isActive: Bool { status.state != .off }

    /// 持续消费提供者的状态流；随宿主视图的 `.task` 生命周期自动取消。
    func observe() async {
        for await newStatus in provider.statusStream {
            status = newStatus
        }
    }

    func toggle() {
        toggleTask?.cancel()
        toggleTask = Task { [weak self] in
            guard let self else { return }
            await self.provider.toggle()
        }
    }
}

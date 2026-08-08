import Foundation

/// Phase 1 Mock AI 字幕状态提供者：模拟 模型加载 → 聆听 → 就绪 的流转。
/// Phase 5 由真实 WhisperKit 管线替换。toggle 可随时取消进行中的流转。
@MainActor
public final class MockSubtitleStatusProvider: SubtitleStatusProviding {
    public private(set) var status: AISubtitleStatus
    public let statusStream: AsyncStream<AISubtitleStatus>

    private let continuation: AsyncStream<AISubtitleStatus>.Continuation
    private var transitionTask: Task<Void, Never>?

    public init(initialStatus: AISubtitleStatus = MockSubtitleStatus.off) {
        self.status = initialStatus
        let pair = AsyncStream<AISubtitleStatus>.makeStream()
        self.statusStream = pair.stream
        self.continuation = pair.continuation
    }

    public func toggle() async {
        transitionTask?.cancel()
        if status.state != .off {
            status = MockSubtitleStatus.off
            continuation.yield(status)
        } else {
            beginActivation()
        }
    }

    /// 模拟 模型加载 → 聆听 → 就绪。
    private func beginActivation() {
        status = AISubtitleStatus(state: .loading, isModelLoaded: false, language: nil)
        continuation.yield(status)

        transitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(1.2))
                try Task.checkCancellation()
                self.status = AISubtitleStatus(state: .listening, isModelLoaded: true, language: "en")
                self.continuation.yield(self.status)

                try await Task.sleep(for: .seconds(1.8))
                try Task.checkCancellation()
                self.status = MockSubtitleStatus.ready
                self.continuation.yield(self.status)
            } catch {
                // 取消：状态保持当前值。
            }
        }
    }
}

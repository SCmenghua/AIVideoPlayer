import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct TranslationBatchCoordinatorTests {

    @Test func initialBatchFiresWhenEnoughContentAndMapsResults() async {
        var received: [UUID: String] = [:]
        var initialCompleted = false

        let coordinator = TranslationBatchCoordinator(
            configuration: .init(
                batchWindow: 60,
                lowWatermark: 20,
                initialFillDuration: 10,
                minimumBatchDuration: 5
            ),
            translator: { texts in
                texts.map { "译-\($0)" }
            },
            onTranslated: { mapping in
                received.merge(mapping) { _, new in new }
            },
            onInitialBatchCompleted: {
                initialCompleted = true
            }
        )

        for index in 0..<3 {
            coordinator.submit(makeSegment(index: index))
        }

        await waitUntil { received.count == 3 }

        #expect(received.count == 3)
        #expect(initialCompleted)
        #expect(coordinator.requestCount == 1)
        #expect(coordinator.didCompleteInitialBatch)
        #expect(coordinator.pendingItems.isEmpty)
    }

    @Test func refillTriggersOnlyWhenReserveLowAndEnoughPending() async {
        var received: [UUID: String] = [:]
        var initialCompleted = false

        let coordinator = TranslationBatchCoordinator(
            configuration: .init(
                batchWindow: 60,
                lowWatermark: 20,
                initialFillDuration: 10,
                minimumBatchDuration: 5
            ),
            translator: { texts in
                texts.map { "译-\($0)" }
            },
            onTranslated: { mapping in
                received.merge(mapping) { _, new in new }
            },
            onInitialBatchCompleted: {
                initialCompleted = true
            }
        )

        for index in 0..<3 {
            coordinator.submit(makeSegment(index: index))
        }
        await waitUntil { received.count == 3 }
        #expect(initialCompleted)
        #expect(coordinator.requestCount == 1)

        for index in 3..<5 {
            coordinator.submit(makeSegment(index: index))
        }
        await waitUntil { received.count == 5 }

        #expect(coordinator.requestCount == 2)
        #expect(received.count == 5)
    }

    @Test func flushPendingNowFiresWithPartialContent() async {
        var received: [UUID: String] = [:]
        let coordinator = TranslationBatchCoordinator(
            configuration: .init(
                batchWindow: 60,
                lowWatermark: 20,
                initialFillDuration: 60,
                minimumBatchDuration: 5
            ),
            translator: { texts in
                texts.map { "译-\($0)" }
            },
            onTranslated: { mapping in
                received.merge(mapping) { _, new in new }
            }
        )

        // 只提交 2 条（约 8s），不足 initialFillDuration(60)：正常 flush 不会触发。
        coordinator.submit(makeSegment(index: 0))
        coordinator.submit(makeSegment(index: 1))
        #expect(coordinator.requestCount == 0)

        // 识别停滞时主动 flush：立即打包发送，即使不足首批窗口。
        coordinator.flushPendingNow()
        await waitUntil { received.count == 2 }

        #expect(received.count == 2)
        #expect(coordinator.requestCount == 1)
        #expect(coordinator.didCompleteInitialBatch)
    }

    @Test func failureRetriesInitialBatchAndKeepsGateClosed() async {
        var received: [UUID: String] = [:]
        var initialCompleted = false

        let coordinator = TranslationBatchCoordinator(
            configuration: .init(
                batchWindow: 60,
                lowWatermark: 20,
                initialFillDuration: 10,
                minimumBatchDuration: 5
            ),
            translator: { _ in
                throw TranslationBatchError.emptyResponse
            },
            onTranslated: { mapping in
                received.merge(mapping) { _, new in new }
            },
            onInitialBatchCompleted: {
                initialCompleted = true
            }
        )

        for index in 0..<3 {
            coordinator.submit(makeSegment(index: index))
        }
        await waitUntil(timeout: 6) { coordinator.requestCount >= 2 }

        #expect(!initialCompleted)
        #expect(coordinator.lastError != nil)
        #expect(received.isEmpty)
        #expect(!coordinator.didCompleteInitialBatch)
    }

    @Test func resetClearsState() async {
        var received: [UUID: String] = [:]
        let coordinator = TranslationBatchCoordinator(
            configuration: .init(
                batchWindow: 60,
                lowWatermark: 20,
                initialFillDuration: 10,
                minimumBatchDuration: 5
            ),
            translator: { texts in
                texts.map { "译-\($0)" }
            },
            onTranslated: { mapping in
                received.merge(mapping) { _, new in new }
            }
        )

        for index in 0..<3 {
            coordinator.submit(makeSegment(index: index))
        }
        await waitUntil { received.count == 3 }
        #expect(coordinator.requestCount == 1)

        coordinator.reset()

        #expect(coordinator.pendingItems.isEmpty)
        #expect(!coordinator.isRequestInFlight)
        #expect(!coordinator.didCompleteInitialBatch)
        #expect(coordinator.translatedThrough == 0)
        #expect(coordinator.translatedAhead == 0)
        #expect(coordinator.lastError == nil)
    }

    // MARK: - Helpers

    private func makeSegment(index: Int) -> SubtitleSegment {
        let start = Double(index) * 4
        return SubtitleSegment(
            startTime: start,
            endTime: start + 4,
            originalText: "line\(index)",
            confidence: 1,
            isPartial: false
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
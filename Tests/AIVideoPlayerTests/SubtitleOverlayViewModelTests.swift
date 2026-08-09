import CoreGraphics
import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleOverlayViewModelTests {

    @Test func consumesSegmentsAndAlignsWholeSentenceToPlaybackCursor() async {
        let pair = AsyncStream<SubtitleSegment>.makeStream()
        let overlay = makeOverlay(stream: pair.stream)
        let consumeTask = Task { await overlay.consume() }

        pair.continuation.yield(makeSegment(start: 10, end: 14, text: "整句"))
        await waitUntil {
            overlay.updatePlaybackTime(10)
            return overlay.activeSegment?.originalText == "整句"
        }

        overlay.updatePlaybackTime(9)
        #expect(overlay.activeSegment == nil)
        overlay.updatePlaybackTime(14)
        #expect(overlay.activeSegment == nil)

        consumeTask.cancel()
        await consumeTask.value
    }

    @Test func partialIsConvergedToFinalByTimeline() async {
        let pair = AsyncStream<SubtitleSegment>.makeStream()
        let overlay = makeOverlay(stream: pair.stream)
        let consumeTask = Task { await overlay.consume() }

        pair.continuation.yield(makeSegment(start: 5, end: 8, text: "hi", isPartial: true))
        await waitUntil {
            overlay.updatePlaybackTime(6)
            return overlay.activeSegment?.originalText == "hi"
        }
        #expect(overlay.activeSegment?.isPartial == true)

        pair.continuation.yield(makeSegment(start: 5.2, end: 7.5, text: "hello"))
        await waitUntil {
            overlay.updatePlaybackTime(6)
            return overlay.activeSegment?.originalText == "hello"
        }
        #expect(overlay.activeSegment?.isPartial == false)

        consumeTask.cancel()
        await consumeTask.value
    }

    @Test func resetClearsTimelineAndActiveSegment() async {
        let pair = AsyncStream<SubtitleSegment>.makeStream()
        let overlay = makeOverlay(stream: pair.stream)
        let consumeTask = Task { await overlay.consume() }

        pair.continuation.yield(makeSegment(start: 0, end: 2, text: "x"))
        await waitUntil {
            overlay.updatePlaybackTime(1)
            return overlay.activeSegment != nil
        }

        await overlay.reset()
        #expect(overlay.activeSegment == nil)
        overlay.updatePlaybackTime(1)
        #expect(overlay.activeSegment == nil)

        consumeTask.cancel()
        await consumeTask.value
    }

    @Test func moveUpdatesPersistedPositionWithClamping() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())
        let overlay = makeOverlay(stream: emptyStream(), displaySettings: settings)
        let container = CGSize(width: 400, height: 800)
        let original = settings.normalizedPosition

        overlay.move(by: CGSize(width: 40, height: -80), in: container)
        #expect(
            settings.normalizedPosition
                == CGPoint(x: original.x + 0.1, y: original.y - 0.1)
        )

        overlay.move(by: CGSize(width: 10_000, height: -10_000), in: container)
        #expect(settings.normalizedPosition.x == SubtitleDisplaySettings.positionRange.upperBound)
        #expect(settings.normalizedPosition.y == SubtitleDisplaySettings.positionRange.lowerBound)
    }

    @Test func fontSizeComesFromDisplaySettings() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())
        let overlay = makeOverlay(stream: emptyStream(), displaySettings: settings)

        #expect(overlay.fontSize == .medium)
        settings.fontSize = SubtitleFontSize.large
        #expect(overlay.fontSize == SubtitleFontSize.large)
    }

    // MARK: - 辅助

    private func uniqueSuiteName() -> String {
        "subtitle-overlay.\(UUID().uuidString)"
    }

    private func makeOverlay(
        stream: AsyncStream<SubtitleSegment>,
        displaySettings: SubtitleDisplaySettings = SubtitleDisplaySettings(
            suiteName: "subtitle-overlay.\(UUID().uuidString)"
        )
    ) -> SubtitleOverlayViewModel {
        SubtitleOverlayViewModel(segments: stream, displaySettings: displaySettings)
    }

    private func emptyStream() -> AsyncStream<SubtitleSegment> {
        AsyncStream { _ in }
    }

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        isPartial: Bool = false
    ) -> SubtitleSegment {
        SubtitleSegment(
            startTime: start,
            endTime: end,
            originalText: text,
            confidence: 0.9,
            isPartial: isPartial
        )
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

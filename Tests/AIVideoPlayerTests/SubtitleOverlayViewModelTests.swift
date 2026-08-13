import CoreGraphics
import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleOverlayViewModelTests {

    @Test func activeSegmentTracksTranscriptAndPlaybackCursor() {
        let store = SubtitleTranscriptStore()
        let overlay = makeOverlay(transcript: store)

        store.append(makeSegment(start: 10, end: 14, text: "整句"))
        overlay.updatePlaybackTime(10)
        #expect(overlay.activeSegment?.originalText == "整句")

        overlay.updatePlaybackTime(9)
        #expect(overlay.activeSegment == nil)
        overlay.updatePlaybackTime(14)
        #expect(overlay.activeSegment == nil)
    }

    @Test func partialIsConvergedToFinalByStore() {
        let store = SubtitleTranscriptStore()
        let overlay = makeOverlay(transcript: store)

        store.append(makeSegment(start: 5, end: 8, text: "hi", isPartial: true))
        overlay.updatePlaybackTime(6)
        #expect(overlay.activeSegment?.originalText == "hi")
        #expect(overlay.activeSegment?.isPartial == true)

        store.append(makeSegment(start: 5.2, end: 7.5, text: "hello"))
        #expect(overlay.activeSegment?.originalText == "hello")
        #expect(overlay.activeSegment?.isPartial == false)
    }

    @Test func resetResetsCursorButKeepsTranscript() {
        let store = SubtitleTranscriptStore()
        let overlay = makeOverlay(transcript: store)

        store.append(makeSegment(start: 10, end: 14, text: "x"))
        overlay.updatePlaybackTime(12)
        #expect(overlay.activeSegment?.originalText == "x")

        // Phase 9.6：reset 只重置光标，不再清空字幕记录（清空由管线负责）。
        overlay.reset()
        #expect(overlay.activeSegment == nil)

        overlay.updatePlaybackTime(12)
        #expect(overlay.activeSegment?.originalText == "x")
    }

    @Test func moveUpdatesPersistedPositionWithClamping() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())
        let overlay = makeOverlay(transcript: SubtitleTranscriptStore(), displaySettings: settings)
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
        let overlay = makeOverlay(transcript: SubtitleTranscriptStore(), displaySettings: settings)

        #expect(overlay.fontSize == .medium)
        settings.fontSize = SubtitleFontSize.large
        #expect(overlay.fontSize == SubtitleFontSize.large)
    }

    @Test func bilingualEnabledComesFromDisplaySettings() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())
        let overlay = makeOverlay(transcript: SubtitleTranscriptStore(), displaySettings: settings)

        #expect(overlay.isBilingualEnabled)
        settings.isBilingualEnabled = false
        #expect(!overlay.isBilingualEnabled)
    }

    // MARK: - 辅助

    private func uniqueSuiteName() -> String {
        "subtitle-overlay.\(UUID().uuidString)"
    }

    private func makeOverlay(
        transcript: SubtitleTranscriptStore,
        displaySettings: SubtitleDisplaySettings = SubtitleDisplaySettings(
            suiteName: "subtitle-overlay.\(UUID().uuidString)"
        )
    ) -> SubtitleOverlayViewModel {
        SubtitleOverlayViewModel(transcript: transcript, displaySettings: displaySettings)
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
}

import CoreGraphics
import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleDisplaySettingsTests {

    @Test func defaultsAreMediumAndLowerCenter() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())

        #expect(settings.fontSize == .medium)
        #expect(settings.normalizedPosition == SubtitleDisplaySettings.defaultPosition)
    }

    @Test func changesPersistAcrossInstances() {
        let suite = uniqueSuiteName()
        let first = SubtitleDisplaySettings(suiteName: suite)
        first.fontSize = .large
        first.setPosition(CGPoint(x: 0.3, y: 0.4))

        let second = SubtitleDisplaySettings(suiteName: suite)
        #expect(second.fontSize == .large)
        #expect(second.normalizedPosition == CGPoint(x: 0.3, y: 0.4))
    }

    @Test func positionIsClampedToRange() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())
        settings.setPosition(CGPoint(x: -1, y: 2))

        #expect(
            settings.normalizedPosition == CGPoint(
                x: SubtitleDisplaySettings.positionRange.lowerBound,
                y: SubtitleDisplaySettings.positionRange.upperBound
            )
        )
    }

    @Test func resetPositionRestoresDefault() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())
        settings.setPosition(CGPoint(x: 0.2, y: 0.2))

        settings.resetPosition()

        #expect(settings.normalizedPosition == SubtitleDisplaySettings.defaultPosition)
    }

    @Test func fontSizesExposePointSizes() {
        #expect(SubtitleFontSize.small.originalPointSize < SubtitleFontSize.medium.originalPointSize)
        #expect(SubtitleFontSize.medium.originalPointSize < SubtitleFontSize.large.originalPointSize)
        #expect(SubtitleFontSize.large.translationPointSize < SubtitleFontSize.large.originalPointSize)
    }

    private func uniqueSuiteName() -> String {
        "subtitle-display.\(UUID().uuidString)"
    }
}

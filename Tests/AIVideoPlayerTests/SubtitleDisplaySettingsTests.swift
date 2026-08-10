import CoreGraphics
import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleDisplaySettingsTests {

    @Test func defaultsAreMediumAndLowerCenter() {
        let settings = SubtitleDisplaySettings(suiteName: uniqueSuiteName())

        #expect(settings.fontSize == .medium)
        #expect(settings.isBilingualEnabled == SubtitleDisplaySettings.defaultIsBilingualEnabled)
        #expect(settings.isBilingualEnabled)
        #expect(settings.normalizedPosition == SubtitleDisplaySettings.defaultPosition)
    }

    @Test func changesPersistAcrossInstances() {
        let suite = uniqueSuiteName()
        let first = SubtitleDisplaySettings(suiteName: suite)
        first.fontSize = .large
        first.isBilingualEnabled = false
        first.setPosition(CGPoint(x: 0.3, y: 0.4))

        let second = SubtitleDisplaySettings(suiteName: suite)
        #expect(second.fontSize == .large)
        #expect(!second.isBilingualEnabled)
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

    @Test func fontSizesExposeTranslationMainAndOriginalHalf() {
        #expect(SubtitleFontSize.small.translationPointSize < SubtitleFontSize.medium.translationPointSize)
        #expect(SubtitleFontSize.medium.translationPointSize < SubtitleFontSize.large.translationPointSize)
        // 双语模式下源语言约为翻译语言的一半（主行为译文）。
        #expect(SubtitleFontSize.medium.originalPointSize < SubtitleFontSize.medium.translationPointSize)
        #expect(
            SubtitleFontSize.medium.originalPointSize
                == SubtitleFontSize.medium.translationPointSize * 0.55
        )
    }

    private func uniqueSuiteName() -> String {
        "subtitle-display.\(UUID().uuidString)"
    }
}

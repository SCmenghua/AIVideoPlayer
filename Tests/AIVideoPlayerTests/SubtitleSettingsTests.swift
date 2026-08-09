import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleSettingsTests {

    @Test func defaultsAreEnabledWithThreeSecondWindow() {
        let suite = uniqueSuiteName()
        let settings = SubtitleSettings(suiteName: suite)

        #expect(settings.isLeadAheadEnabled)
        #expect(settings.leadAheadWindow == SubtitleSettings.defaultLeadAheadWindow)

        clearSuite(suite)
    }

    @Test func persistsChanges() {
        let suite = uniqueSuiteName()
        let settings = SubtitleSettings(suiteName: suite)
        settings.isLeadAheadEnabled = false
        settings.leadAheadWindow = 6

        let reloaded = SubtitleSettings(suiteName: suite)
        #expect(!reloaded.isLeadAheadEnabled)
        #expect(reloaded.leadAheadWindow == 6)

        clearSuite(suite)
    }

    @Test func clampsWindowToSupportedRange() {
        let suite = uniqueSuiteName()
        let settings = SubtitleSettings(suiteName: suite)

        settings.leadAheadWindow = 99
        #expect(settings.leadAheadWindow == SubtitleSettings.leadAheadWindowRange.upperBound)

        settings.leadAheadWindow = 0.5
        #expect(settings.leadAheadWindow == SubtitleSettings.leadAheadWindowRange.lowerBound)

        clearSuite(suite)
    }

    private func uniqueSuiteName() -> String {
        "subtitle-settings.\(UUID().uuidString)"
    }

    private func clearSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

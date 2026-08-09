import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct TranslationSettingsTests {

    @Test func defaultsAreDisabledWithFastNMTAndChinese() {
        let suite = uniqueSuiteName()
        let settings = TranslationSettings(suiteName: suite)

        #expect(!settings.isEnabled)
        #expect(settings.selectedProviderID == .fastNMT)
        #expect(settings.targetLanguageCode == TranslationSettings.defaultTargetLanguageCode)
        #expect(!settings.isContextPolishEnabled)
        #expect(settings.localModelDownloadedID == nil)
        #expect(settings.selectedLocalModelID == LocalModelCatalog.gemma4E2B.id)

        clearSuite(suite)
    }

    @Test func persistsProviderAndCloudConfiguration() {
        let suite = uniqueSuiteName()
        let settings = TranslationSettings(suiteName: suite)
        settings.isEnabled = true
        settings.selectedProviderID = .cloudLLM
        settings.targetLanguageCode = "en"
        settings.isContextPolishEnabled = true
        settings.cloudBaseURL = "https://api.example.com/v1"
        settings.cloudModelName = "test-model"
        settings.cloudPrivacyConsentAcknowledged = true
        settings.localModelDownloadedID = LocalModelCatalog.gemma4E2B.id

        let reloaded = TranslationSettings(suiteName: suite)
        #expect(reloaded.isEnabled)
        #expect(reloaded.selectedProviderID == .cloudLLM)
        #expect(reloaded.targetLanguageCode == "en")
        #expect(reloaded.isContextPolishEnabled)
        #expect(reloaded.cloudBaseURL == "https://api.example.com/v1")
        #expect(reloaded.cloudModelName == "test-model")
        #expect(reloaded.cloudPrivacyConsentAcknowledged)
        #expect(reloaded.localModelDownloadedID == LocalModelCatalog.gemma4E2B.id)

        clearSuite(suite)
    }

    @Test func engineCacheKeyChangesWhenProviderOrConfigChanges() {
        let suite = uniqueSuiteName()
        let settings = TranslationSettings(suiteName: suite)

        let fastNMTKey = settings.engineCacheKey
        settings.selectedProviderID = .cloudLLM
        let cloudKey = settings.engineCacheKey
        #expect(fastNMTKey != cloudKey)

        settings.cloudBaseURL = "https://api.example.com/v1"
        let cloudWithURLKey = settings.engineCacheKey
        #expect(cloudKey != cloudWithURLKey)

        settings.selectedProviderID = .fastNMT
        // 缓存键包含云端配置，切回 Fast NMT 后键值应随之变化。
        #expect(settings.engineCacheKey != cloudWithURLKey)
        #expect(settings.engineCacheKey != fastNMTKey)

        clearSuite(suite)
    }

    @Test func targetLanguageCatalogExposesSimplifiedChineseAndEnglish() {
        let languages = TranslationTargetLanguageCatalog.all
        #expect(languages.map(\.code) == ["zh-Hans", "en"])
        #expect(TranslationTargetLanguageCatalog.language(for: "zh-Hans").promptName == "Simplified Chinese")
        #expect(TranslationTargetLanguageCatalog.language(for: "xx").code == "zh-Hans")
    }

    private func uniqueSuiteName() -> String {
        "translation-settings.\(UUID().uuidString)"
    }

    private func clearSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

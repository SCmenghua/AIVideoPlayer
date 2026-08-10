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
        #expect(settings.sourceLanguageCode == nil)
        #expect(settings.targetLanguageCode == TranslationSettings.defaultTargetLanguageCode)
        #expect(settings.visibleLanguageCodes == TranslationLanguageCatalog.all.map(\.code))
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
        settings.sourceLanguageCode = "zh-Hans"
        settings.targetLanguageCode = "en"
        settings.visibleLanguageCodes = ["en", "ja", "zh-Hans"]
        settings.isContextPolishEnabled = true
        settings.cloudBaseURL = "https://api.example.com/v1"
        settings.cloudModelName = "test-model"
        settings.cloudPrivacyConsentAcknowledged = true
        settings.localModelDownloadedID = LocalModelCatalog.gemma4E2B.id

        let reloaded = TranslationSettings(suiteName: suite)
        #expect(reloaded.isEnabled)
        #expect(reloaded.selectedProviderID == .cloudLLM)
        #expect(reloaded.sourceLanguageCode == "zh-Hans")
        #expect(reloaded.targetLanguageCode == "en")
        #expect(reloaded.visibleLanguageCodes == ["en", "ja", "zh-Hans"])
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

        settings.sourceLanguageCode = "zh-Hans"
        let cloudWithSourceKey = settings.engineCacheKey
        #expect(cloudWithURLKey != cloudWithSourceKey)

        settings.selectedProviderID = .fastNMT
        // 缓存键包含云端配置，切回 Fast NMT 后键值应随之变化。
        #expect(settings.engineCacheKey != cloudWithURLKey)
        #expect(settings.engineCacheKey != fastNMTKey)

        clearSuite(suite)
    }

    @Test func languageCatalogExposesTwelveLanguages() {
        let languages = TranslationLanguageCatalog.all
        #expect(languages.count == 12)
        #expect(languages.map(\.code) == [
            "zh-Hans", "en", "ja", "ko", "ms", "fil",
            "th", "vi", "id", "fr", "de", "es",
        ])
        #expect(TranslationLanguageCatalog.language(for: "ja").promptName == "Japanese")
        #expect(TranslationLanguageCatalog.language(for: "ms").promptName == "Malay")
        #expect(TranslationLanguageCatalog.language(for: "fil").promptName == "Filipino")
        #expect(TranslationLanguageCatalog.language(for: "xx").code == "zh-Hans")
    }

    @Test func sourceAndTargetCatalogsFollowLanguagePool() {
        let languages = TranslationSourceLanguageCatalog.all
        #expect(languages.count == 13)
        #expect(languages.first?.code == nil)
        #expect(languages.map(\.code).compactMap { $0 } == TranslationLanguageCatalog.all.map(\.code))
        #expect(TranslationSourceLanguageCatalog.language(for: nil).code == nil)
        #expect(TranslationSourceLanguageCatalog.language(for: "zh-Hans").promptName == "Simplified Chinese")
        #expect(TranslationSourceLanguageCatalog.language(for: "zh").promptName == "Simplified Chinese")
        #expect(TranslationSourceLanguageCatalog.language(for: "xx").code == nil)

        let targets = TranslationTargetLanguageCatalog.all
        #expect(targets.count == 12)
        #expect(targets.map(\.code) == TranslationLanguageCatalog.all.map(\.code))
    }

    @Test func visibleLanguageListTogglesAndSorts() {
        let suite = uniqueSuiteName()
        let settings = TranslationSettings(suiteName: suite)

        settings.toggleLanguageVisibility("ms")
        #expect(!settings.visibleLanguageCodes.contains("ms"))

        settings.toggleLanguageVisibility("ms")
        #expect(settings.visibleLanguageCodes.contains("ms"))

        settings.visibleLanguageCodes = ["en", "ja", "zh-Hans"]
        settings.moveLanguageUp("ja")
        #expect(settings.visibleLanguageCodes == ["ja", "en", "zh-Hans"])
        settings.moveLanguageDown("ja")
        #expect(settings.visibleLanguageCodes == ["en", "ja", "zh-Hans"])

        let reloaded = TranslationSettings(suiteName: suite)
        #expect(reloaded.visibleLanguageCodes == ["en", "ja", "zh-Hans"])

        clearSuite(suite)
    }

    private func uniqueSuiteName() -> String {
        "translation-settings.\(UUID().uuidString)"
    }

    private func clearSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

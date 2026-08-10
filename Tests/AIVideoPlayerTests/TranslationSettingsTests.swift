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
        #expect(settings.sourceLanguageCode == TranslationSettings.defaultSourceLanguageCode)
        #expect(settings.sourceLanguageCode == TranslationSourceLanguageCatalog.autoCode)
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
        settings.sourceLanguageCode = "ja"
        settings.isContextPolishEnabled = true
        settings.cloudBaseURL = "https://api.example.com/v1"
        settings.cloudModelName = "test-model"
        settings.cloudPrivacyConsentAcknowledged = true
        settings.localModelDownloadedID = LocalModelCatalog.gemma4E2B.id

        let reloaded = TranslationSettings(suiteName: suite)
        #expect(reloaded.isEnabled)
        #expect(reloaded.selectedProviderID == .cloudLLM)
        #expect(reloaded.targetLanguageCode == "en")
        #expect(reloaded.sourceLanguageCode == "ja")
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

        // 语言变化也进入缓存键：切换源 / 目标语言应触发翻译引擎重建。
        let fastNMTKeyAfterCloud = settings.engineCacheKey
        settings.sourceLanguageCode = "ja"
        #expect(settings.engineCacheKey != fastNMTKeyAfterCloud)
        let jaKey = settings.engineCacheKey
        settings.targetLanguageCode = "en"
        #expect(settings.engineCacheKey != jaKey)

        clearSuite(suite)
    }

    @Test func targetLanguageCatalogExposesTwelveLanguages() {
        let languages = TranslationTargetLanguageCatalog.all
        #expect(languages.map(\.code) == [
            "zh-Hans", "en", "ja", "ko", "ms", "fil",
            "th", "vi", "id", "fr", "de", "es",
        ])
        #expect(TranslationTargetLanguageCatalog.language(for: "zh-Hans").promptName == "Simplified Chinese")
        #expect(TranslationTargetLanguageCatalog.language(for: "zh-Hans").whisperCode == "zh")
        #expect(TranslationTargetLanguageCatalog.language(for: "ja").whisperCode == "ja")
        #expect(TranslationTargetLanguageCatalog.language(for: "xx").code == "zh-Hans")
    }

    @Test func sourceLanguageCatalogResolvesTranslationAndRecognitionCodes() {
        // 自动检测 + 12 种语言。
        #expect(TranslationSourceLanguageCatalog.all.count == 13)
        #expect(TranslationSourceLanguageCatalog.language(for: "auto")?.displayName == "自动检测")
        #expect(TranslationSourceLanguageCatalog.language(for: "zh")?.translationCode == "zh-Hans")
        #expect(TranslationSourceLanguageCatalog.language(for: "ja")?.translationCode == "ja")

        // 手动指定：识别用 Whisper 代码，翻译用翻译代码。
        #expect(TranslationSourceLanguageCatalog.recognitionCode(for: "zh", detected: nil) == "zh")
        #expect(TranslationSourceLanguageCatalog.translationCode(for: "zh", detected: nil) == "zh-Hans")

        // 自动检测：识别用已检测语言，翻译映射到翻译代码。
        #expect(TranslationSourceLanguageCatalog.recognitionCode(for: "auto", detected: "zh") == "zh")
        #expect(TranslationSourceLanguageCatalog.translationCode(for: "auto", detected: "zh") == "zh-Hans")
        #expect(TranslationSourceLanguageCatalog.translationCode(for: "auto", detected: nil) == nil)

        // 已检测语言不在语言池时原样返回（如 Whisper 的 "yue" 等）。
        #expect(TranslationSourceLanguageCatalog.translationCode(for: "auto", detected: "yue") == "yue")
    }

    private func uniqueSuiteName() -> String {
        "translation-settings.\(UUID().uuidString)"
    }

    private func clearSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

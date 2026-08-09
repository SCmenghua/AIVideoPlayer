import Foundation

/// 依据设置创建当前 Provider（依赖注入入口）。
@MainActor
public enum TranslationProviderFactory {
    public static func make(
        settings: TranslationSettings,
        apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore()
    ) -> (any TranslationEngine)? {
        switch settings.selectedProviderID {
        case .fastNMT:
            FastNMTTranslator()
        case .localLLM:
            LocalLLMTranslator(
                modelDescriptor: LocalModelCatalog.descriptor(
                    for: settings.selectedLocalModelID
                ) ?? LocalModelCatalog.gemma4E2B
            )
        case .cloudLLM:
            CloudLLMTranslator(settings: settings, apiKeyStore: apiKeyStore)
        }
    }
}

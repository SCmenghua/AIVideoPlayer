import Foundation
import Translation

/// 本地轻量翻译（Apple Translation 框架，完全本地，文本不出设备）。
/// 依赖系统语言包：语言包未安装 / 语言对不支持时给出可读提示。
@MainActor
public final class FastNMTTranslator: TranslationEngine {
    public var providerID: TranslationProviderID { .fastNMT }
    public var displayName: String { TranslationProviderCatalog.fastNMT.displayName }
    public var isFullyLocal: Bool { true }
    public var supportsContextPolish: Bool { false }
    public var isReady: Bool { true }

    /// 语言可用性检查（默认走 `LanguageAvailability`；测试可注入）。
    public typealias AvailabilityCheck =
        @Sendable (Locale.Language, Locale.Language) async -> LanguageAvailability.Status
    /// 实际翻译（默认走 `TranslationSession`；测试可注入）。
    public typealias TranslateClosure =
        @Sendable (String, Locale.Language, Locale.Language) async throws -> String

    private let availabilityCheck: AvailabilityCheck
    private let translateText: TranslateClosure

    public init(
        availabilityCheck: @escaping AvailabilityCheck = FastNMTTranslator.systemAvailability,
        translateText: @escaping TranslateClosure = FastNMTTranslator.systemTranslate
    ) {
        self.availabilityCheck = availabilityCheck
        self.translateText = translateText
    }

    public func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String,
        context: TranslationContext?
    ) async throws -> String {
        let source = Locale.Language(identifier: sourceLanguage ?? "en")
        let target = Locale.Language(identifier: targetLanguage)
        let status = await availabilityCheck(source, target)
        switch status {
        case .installed:
            break
        case .supported:
            throw FastNMTError.languagePackNotInstalled
        case .unsupported:
            throw FastNMTError.unsupportedLanguagePair
        @unknown default:
            throw FastNMTError.languagePackNotInstalled
        }
        let result = try await translateText(text, source, target)
        guard !result.isEmpty else { throw FastNMTError.emptyResult }
        return result
    }

    nonisolated static func systemAvailability(
        _ source: Locale.Language, _ target: Locale.Language
    ) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    nonisolated static func systemTranslate(
        _ text: String, source: Locale.Language, target: Locale.Language
    ) async throws -> String {
        // iOS 26+ 支持无 UI 场景直接初始化（语言包已安装时无需用户交互）。
        let session = TranslationSession(installedSource: source, target: target)
        try await session.prepareTranslation()
        let response = try await session.translate(text)
        return response.targetText
    }
}

/// Fast NMT（Apple 原生翻译）错误。
public enum FastNMTError: LocalizedError, Sendable {
    case languagePackNotInstalled
    case unsupportedLanguagePair
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .languagePackNotInstalled:
            "系统语言包未安装，请先在系统设置的「翻译」中下载对应语言。"
        case .unsupportedLanguagePair:
            "系统翻译不支持当前语言对。"
        case .emptyResult:
            "系统翻译返回了空内容。"
        }
    }
}

import Foundation
import Observation

/// 翻译设置（Phase 7），UserDefaults 持久化。
/// 注意：云端 API Key 不存 UserDefaults，单独存 Keychain（`APIKeyStoring`）。
@MainActor
@Observable
public final class TranslationSettings {
    public static let defaultTargetLanguageCode = TranslationTargetLanguageCatalog.simplifiedChinese.code
    public static let defaultSourceLanguageCode = TranslationSourceLanguageCatalog.autoCode

    /// 翻译总开关（默认关闭；启用对应 Provider 前需满足就绪条件）。
    public var isEnabled: Bool {
        didSet { persist() }
    }

    /// 当前选择的 Provider。
    public var selectedProviderID: TranslationProviderID {
        didSet { persist() }
    }

    /// 目标语言代码（如 zh-Hans / en）。
    public var targetLanguageCode: String {
        didSet { persist() }
    }

    /// 源语言代码（视频语音；"auto" = 自动检测，其余为 Whisper 代码如 zh / ja / en）。
    public var sourceLanguageCode: String {
        didSet { persist() }
    }

    /// 剧情理解润色（仅本地 / 云端 LLM 生效）。
    public var isContextPolishEnabled: Bool {
        didSet { persist() }
    }

    // MARK: - 云端配置（非敏感部分；apiKey 走 Keychain）

    public var cloudBaseURL: String {
        didSet { persist() }
    }

    public var cloudModelName: String {
        didSet { persist() }
    }

    /// 用户已确认隐私提示（字幕文本将发送到配置的翻译服务）。
    public var cloudPrivacyConsentAcknowledged: Bool {
        didSet { persist() }
    }

    // MARK: - 本地模型

    /// 当前选择的本地模型 ID。
    public var selectedLocalModelID: String {
        didSet { persist() }
    }

    /// 已成功下载的模型 ID（nil = 未下载）。
    public var localModelDownloadedID: String? {
        didSet { persist() }
    }

    private static let enabledKey = "translation.enabled.v1"
    private static let providerKey = "translation.provider.v1"
    private static let targetLanguageKey = "translation.targetLanguage.v1"
    private static let sourceLanguageKey = "translation.sourceLanguage.v1"
    private static let contextPolishKey = "translation.contextPolish.v1"
    private static let cloudBaseURLKey = "translation.cloud.baseURL.v1"
    private static let cloudModelKey = "translation.cloud.model.v1"
    private static let cloudConsentKey = "translation.cloud.consent.v1"
    private static let localModelKey = "translation.local.model.v1"
    private static let localDownloadedKey = "translation.local.downloaded.v1"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        // 翻译默认开启（默认 Provider 为完全本地的 Fast NMT，无需隐私确认）：
        // 用户打开 AI 字幕即可看到译文，避免「只显示原文」的困惑。
        self.isEnabled = defaults.object(forKey: Self.enabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.enabledKey)
        self.selectedProviderID = TranslationProviderID(
            rawValue: defaults.string(forKey: Self.providerKey) ?? ""
        ) ?? .fastNMT
        self.targetLanguageCode = defaults.string(forKey: Self.targetLanguageKey)
            ?? Self.defaultTargetLanguageCode
        self.sourceLanguageCode = defaults.string(forKey: Self.sourceLanguageKey)
            ?? Self.defaultSourceLanguageCode
        self.isContextPolishEnabled = defaults.bool(forKey: Self.contextPolishKey)
        self.cloudBaseURL = defaults.string(forKey: Self.cloudBaseURLKey) ?? ""
        self.cloudModelName = defaults.string(forKey: Self.cloudModelKey) ?? ""
        self.cloudPrivacyConsentAcknowledged = defaults.bool(forKey: Self.cloudConsentKey)
        self.selectedLocalModelID = defaults.string(forKey: Self.localModelKey)
            ?? LocalModelCatalog.gemma4E2B.id
        self.localModelDownloadedID = defaults.string(forKey: Self.localDownloadedKey)
    }

    /// 引擎缓存键：Provider 与其配置变化时字幕管道重建翻译引擎。
    public var engineCacheKey: String {
        [
            selectedProviderID.rawValue,
            sourceLanguageCode,
            targetLanguageCode,
            cloudBaseURL,
            cloudModelName,
            selectedLocalModelID,
            localModelDownloadedID ?? "",
        ].joined(separator: "|")
    }

    public func persist() {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(selectedProviderID.rawValue, forKey: Self.providerKey)
        defaults.set(targetLanguageCode, forKey: Self.targetLanguageKey)
        defaults.set(sourceLanguageCode, forKey: Self.sourceLanguageKey)
        defaults.set(isContextPolishEnabled, forKey: Self.contextPolishKey)
        defaults.set(cloudBaseURL, forKey: Self.cloudBaseURLKey)
        defaults.set(cloudModelName, forKey: Self.cloudModelKey)
        defaults.set(cloudPrivacyConsentAcknowledged, forKey: Self.cloudConsentKey)
        defaults.set(selectedLocalModelID, forKey: Self.localModelKey)
        defaults.set(localModelDownloadedID ?? "", forKey: Self.localDownloadedKey)
    }
}

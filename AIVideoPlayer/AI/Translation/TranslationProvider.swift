import Foundation

/// 可替换翻译 Provider 标识。
public enum TranslationProviderID: String, Codable, Sendable, CaseIterable, Hashable {
    /// 本地轻量翻译（Apple Translation，完全本地）。
    case fastNMT
    /// 本地大模型（按需下载，完全离线）。
    case localLLM
    /// 云端 OpenAI 兼容 API。
    case cloudLLM
}

/// Provider 的静态元数据，供设置页渲染。
public struct TranslationProviderDescriptor: Sendable, Hashable {
    public let id: TranslationProviderID
    public let displayName: String
    public let isFullyLocal: Bool
    public let supportsContextPolish: Bool
    public let detail: String

    public init(
        id: TranslationProviderID,
        displayName: String,
        isFullyLocal: Bool,
        supportsContextPolish: Bool,
        detail: String
    ) {
        self.id = id
        self.displayName = displayName
        self.isFullyLocal = isFullyLocal
        self.supportsContextPolish = supportsContextPolish
        self.detail = detail
    }
}

/// 三个 Provider 的静态目录。
public enum TranslationProviderCatalog {
    public static let fastNMT = TranslationProviderDescriptor(
        id: .fastNMT,
        displayName: "本地轻量翻译（Apple）",
        isFullyLocal: true,
        supportsContextPolish: false,
        detail: "使用 Apple 原生翻译，完全本地运行，文本不出设备，无需配置。"
    )
    public static let localLLM = TranslationProviderDescriptor(
        id: .localLLM,
        displayName: "本地大模型（Gemma 4 E2B）",
        isFullyLocal: true,
        supportsContextPolish: true,
        detail: "模型按需从 Hugging Face 下载（约 3.5 GB），完全离线运行，支持剧情理解润色。"
    )
    public static let cloudLLM = TranslationProviderDescriptor(
        id: .cloudLLM,
        displayName: "云端 API（OpenAI 兼容）",
        isFullyLocal: false,
        supportsContextPolish: true,
        detail: "配置 Base URL / API Key / Model 后启用；字幕文本将发送到你配置的翻译服务。"
    )

    public static let all: [TranslationProviderDescriptor] = [fastNMT, localLLM, cloudLLM]

    public static func descriptor(for id: TranslationProviderID) -> TranslationProviderDescriptor {
        all.first { $0.id == id } ?? fastNMT
    }
}

/// 目标语言（设置页选项；后续可扩展更多语言）。
public struct TranslationTargetLanguage: Sendable, Hashable {
    public let code: String
    public let displayName: String
    /// 用于 Prompt 的英文语言名。
    public let promptName: String

    public init(code: String, displayName: String, promptName: String) {
        self.code = code
        self.displayName = displayName
        self.promptName = promptName
    }
}

public enum TranslationTargetLanguageCatalog {
    public static let simplifiedChinese = TranslationTargetLanguage(
        code: "zh-Hans",
        displayName: "简体中文",
        promptName: "Simplified Chinese"
    )
    public static let english = TranslationTargetLanguage(
        code: "en",
        displayName: "English",
        promptName: "English"
    )

    public static let all: [TranslationTargetLanguage] = [simplifiedChinese, english]

    public static func language(for code: String) -> TranslationTargetLanguage {
        all.first { $0.code == code } ?? simplifiedChinese
    }
}

/// 源语言（设置页选项；nil 表示自动检测）。
public struct TranslationSourceLanguage: Sendable, Hashable {
    /// Locale 风格语言代码（如 zh-Hans / en）；nil = 自动检测。
    public let code: String?
    public let displayName: String
    /// 用于本地 LLM Prompt 的英文语言名；nil 时由 LLM 自行判断。
    public let promptName: String?

    public init(code: String?, displayName: String, promptName: String?) {
        self.code = code
        self.displayName = displayName
        self.promptName = promptName
    }
}

public enum TranslationSourceLanguageCatalog {
    public static let automatic = TranslationSourceLanguage(
        code: nil,
        displayName: "自动检测",
        promptName: nil
    )
    public static let simplifiedChinese = TranslationSourceLanguage(
        code: "zh-Hans",
        displayName: "简体中文",
        promptName: "Chinese"
    )
    public static let english = TranslationSourceLanguage(
        code: "en",
        displayName: "English",
        promptName: "English"
    )

    public static let all: [TranslationSourceLanguage] = [
        automatic, simplifiedChinese, english,
    ]

    public static func language(for code: String?) -> TranslationSourceLanguage {
        guard let code else { return automatic }
        if let exact = all.first(where: { $0.code == code }) {
            return exact
        }
        // 兼容 Whisper 的 ISO 639-1 代码（如 "zh" → "zh-Hans"）。
        return all.first { $0.code?.lowercased().hasPrefix(code.lowercased()) == true }
            ?? automatic
    }
}

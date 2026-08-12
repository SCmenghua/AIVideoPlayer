import Foundation

/// 可替换翻译 Provider 标识。
public enum TranslationProviderID: String, Codable, Sendable, CaseIterable, Hashable {
    /// 系统内置翻译（Apple Translation，完全本地）。
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
        displayName: "系统内置翻译（Apple）",
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

/// 字幕语言（设置页选项）：目标语言（翻译输出）与源语言（视频语音）共用同一语言池。
/// `code` 为翻译 / Locale 语言代码（如 zh-Hans / ja）；`whisperCode` 为识别引擎代码
/// （ISO-639-1，如 zh / ja），中文两者不同，其余语言一致。
public struct TranslationTargetLanguage: Sendable, Hashable {
    public let code: String
    public let whisperCode: String
    public let displayName: String
    /// 用于 Prompt 的英文语言名。
    public let promptName: String

    public init(code: String, whisperCode: String, displayName: String, promptName: String) {
        self.code = code
        self.whisperCode = whisperCode
        self.displayName = displayName
        self.promptName = promptName
    }
}

public enum TranslationTargetLanguageCatalog {
    public static let simplifiedChinese = TranslationTargetLanguage(
        code: "zh-Hans", whisperCode: "zh",
        displayName: "简体中文",
        promptName: "Simplified Chinese"
    )
    public static let english = TranslationTargetLanguage(
        code: "en", whisperCode: "en",
        displayName: "English",
        promptName: "English"
    )
    public static let japanese = TranslationTargetLanguage(
        code: "ja", whisperCode: "ja",
        displayName: "日本語",
        promptName: "Japanese"
    )
    public static let korean = TranslationTargetLanguage(
        code: "ko", whisperCode: "ko",
        displayName: "한국어",
        promptName: "Korean"
    )
    public static let malay = TranslationTargetLanguage(
        code: "ms", whisperCode: "ms",
        displayName: "Bahasa Melayu",
        promptName: "Malay"
    )
    public static let filipino = TranslationTargetLanguage(
        code: "fil", whisperCode: "fil",
        displayName: "Filipino",
        promptName: "Filipino"
    )
    public static let thai = TranslationTargetLanguage(
        code: "th", whisperCode: "th",
        displayName: "ไทย",
        promptName: "Thai"
    )
    public static let vietnamese = TranslationTargetLanguage(
        code: "vi", whisperCode: "vi",
        displayName: "Tiếng Việt",
        promptName: "Vietnamese"
    )
    public static let indonesian = TranslationTargetLanguage(
        code: "id", whisperCode: "id",
        displayName: "Bahasa Indonesia",
        promptName: "Indonesian"
    )
    public static let french = TranslationTargetLanguage(
        code: "fr", whisperCode: "fr",
        displayName: "Français",
        promptName: "French"
    )
    public static let german = TranslationTargetLanguage(
        code: "de", whisperCode: "de",
        displayName: "Deutsch",
        promptName: "German"
    )
    public static let spanish = TranslationTargetLanguage(
        code: "es", whisperCode: "es",
        displayName: "Español",
        promptName: "Spanish"
    )

    public static let all: [TranslationTargetLanguage] = [
        simplifiedChinese, english, japanese, korean, malay, filipino,
        thai, vietnamese, indonesian, french, german, spanish,
    ]

    public static func language(for code: String) -> TranslationTargetLanguage {
        all.first { $0.code == code } ?? simplifiedChinese
    }
}

/// 源语言（视频语音）选项：`code` 为 Whisper 识别代码（ISO-639-1），
/// `translationCode` 为翻译时使用的代码（如 zh → zh-Hans）。
public struct TranslationSourceLanguage: Sendable, Hashable {
    public let code: String
    public let translationCode: String
    public let displayName: String
    public let promptName: String

    public init(code: String, translationCode: String, displayName: String, promptName: String) {
        self.code = code
        self.translationCode = translationCode
        self.displayName = displayName
        self.promptName = promptName
    }
}

public enum TranslationSourceLanguageCatalog {
    /// 自动检测的识别代码（默认值）。
    public static let autoCode = "auto"
    public static let auto = TranslationSourceLanguage(
        code: autoCode,
        translationCode: "en",
        displayName: "自动检测",
        promptName: "Auto-detect"
    )

    /// 可选源语言：自动检测 + 12 种语言（与目标语言池一致）。
    public static var all: [TranslationSourceLanguage] {
        [auto] + TranslationTargetLanguageCatalog.all.map {
            TranslationSourceLanguage(
                code: $0.whisperCode,
                translationCode: $0.code,
                displayName: $0.displayName,
                promptName: $0.promptName
            )
        }
    }

    /// 按 Whisper 识别代码查找源语言；找不到返回 nil。
    public static func language(for code: String) -> TranslationSourceLanguage? {
        all.first { $0.code == code }
    }

    /// 解析翻译源语言代码：手动选择 → 其翻译代码；自动检测 → 识别语言对应的翻译代码
    /// （识别语言不在语言池时原样返回，如 "en"）。
    public static func translationCode(
        for selectedCode: String,
        detected: String?
    ) -> String? {
        if selectedCode == autoCode {
            guard let detected else { return nil }
            return language(for: detected)?.translationCode ?? detected
        }
        return language(for: selectedCode)?.translationCode ?? selectedCode
    }

    /// 解析识别语言代码：手动选择 → 其 Whisper 代码；自动检测 → 已检测语言（首窗 nil）。
    public static func recognitionCode(
        for selectedCode: String,
        detected: String?
    ) -> String? {
        if selectedCode == autoCode { return detected }
        return language(for: selectedCode)?.code ?? selectedCode
    }
}

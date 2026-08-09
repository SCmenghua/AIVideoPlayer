import Foundation

/// 一次翻译请求的剧情上下文（已由 `TranslationContextProvider` 压缩；
/// 禁止把大段原始字幕直接塞进请求）。
public struct TranslationContext: Sendable, Equatable {
    public let text: String

    public init(text: String = "") {
        self.text = text
    }

    public var isEmpty: Bool { text.isEmpty }
}

/// 文本翻译。Phase 7 接入可替换的翻译服务；
/// 调用方启用非本地 Provider 前必须先行展示隐私提示（字幕文本将发送到该服务）。
/// 译文写入 `SubtitleSegment.translatedText`。
@MainActor
public protocol TranslationEngine: AnyObject, Sendable {
    /// Provider 标识（设置页选择与持久化）。
    var providerID: TranslationProviderID { get }
    /// 设置页展示名称。
    var displayName: String { get }
    /// 是否完全本地运行（文本不出设备）。
    var isFullyLocal: Bool { get }
    /// 是否支持剧情理解润色（本地 / 云端 LLM）。
    var supportsContextPolish: Bool { get }
    /// 是否已具备翻译能力（本地大模型需模型已下载；云端需配置完成）。
    var isReady: Bool { get }

    func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String,
        context: TranslationContext?
    ) async throws -> String
}

/// 云端 Provider 能力：配置后「测试连接」（验证 baseUrl / apiKey / modelName 可用）。
@MainActor
public protocol TranslationConnectionTesting: AnyObject, Sendable {
    func testConnection() async throws
}

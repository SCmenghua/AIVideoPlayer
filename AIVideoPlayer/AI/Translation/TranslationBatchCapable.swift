import Foundation

/// 批量翻译请求（Phase 9.3.1）：一次翻译多条字幕文本。
public struct TranslationBatchRequest: Sendable {
    public let texts: [String]
    public let sourceLanguage: String?
    public let targetLanguage: String
    public let context: TranslationContext?

    public init(
        texts: [String],
        sourceLanguage: String?,
        targetLanguage: String,
        context: TranslationContext? = nil
    ) {
        self.texts = texts
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.context = context
    }
}

/// 批量翻译能力（Phase 9.3.1）：LLM 类 Provider 可选实现，
/// 把多条字幕一次翻译，降低请求频率并隐藏单条翻译延迟。
/// 系统内置翻译（Fast NMT）不实现此协议，继续走逐条翻译。
@MainActor
public protocol TranslationBatchCapable: TranslationEngine {
    /// 一次翻译多条文本，返回与输入等长、同序的译文数组。
    func translateBatch(_ request: TranslationBatchRequest) async throws -> [String]
}
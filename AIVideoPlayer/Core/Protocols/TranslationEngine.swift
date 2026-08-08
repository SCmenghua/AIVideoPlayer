import Foundation

/// 文本翻译。Phase 7 接入用户自配置的翻译服务；
/// 调用方必须先行展示隐私提示（字幕文本将发送到该服务）。
@MainActor
public protocol TranslationEngine: AnyObject {
    func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String
    ) async throws -> String
}

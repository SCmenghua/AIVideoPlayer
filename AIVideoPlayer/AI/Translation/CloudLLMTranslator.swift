import Foundation
import UIKit

/// 云端翻译错误（可读提示）。
public enum CloudLLMError: LocalizedError, Sendable {
    case invalidBaseURL
    case emptyAPIKey
    case emptyModelName
    case networkError(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 无效，请输入合法的服务地址。"
        case .emptyAPIKey:
            "请先填写 API Key。"
        case .emptyModelName:
            "请先填写模型名称（如 deepseek-chat）。"
        case .networkError(let message):
            "无法连接翻译服务：\(message)"
        case .httpError(let statusCode, let message):
            "翻译服务请求失败（HTTP \(statusCode)）：\(message)"
        case .invalidResponse:
            "翻译服务返回了无法解析的响应。"
        case .emptyContent:
            "翻译服务返回了空内容。"
        }
    }
}

/// 云端 LLM Provider（OpenAI 兼容 ChatCompletions）。
/// apiKey 存 Keychain；启用前必须展示隐私提示；「测试连接」成功后才允许启用。
@MainActor
public final class CloudLLMTranslator: TranslationEngine, TranslationConnectionTesting, TranslationBatchCapable {
    public var providerID: TranslationProviderID { .cloudLLM }
    public var displayName: String { TranslationProviderCatalog.cloudLLM.displayName }
    public var isFullyLocal: Bool { false }
    public var supportsContextPolish: Bool { true }

    public var isReady: Bool {
        !settings.cloudBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.cloudModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? apiKeyStore.loadAPIKey())?.isEmpty == false
    }

    private let settings: TranslationSettings
    private let apiKeyStore: any APIKeyStoring
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(
        settings: TranslationSettings,
        apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        session: URLSession = .shared
    ) {
        self.settings = settings
        self.apiKeyStore = apiKeyStore
        self.session = session
    }

    public func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String,
        context: TranslationContext?
    ) async throws -> String {
        let config = try resolvedConfig()
        let prompt = Self.buildPrompt(
            text: text,
            targetLanguage: targetLanguage,
            context: context
        )
        let request = try makeRequest(config: config, prompt: prompt)
        let data = try await perform(request: request)
        return try Self.extractContent(from: data, decoder: decoder)
    }

    public func testConnection() async throws {
        let config = try resolvedConfig()
        let request = try makeRequest(config: config, prompt: "你好")
        let data = try await perform(request: request)
        _ = try Self.extractContent(from: data, decoder: decoder)
    }

    public func translateBatch(_ request: TranslationBatchRequest) async throws -> [String] {
        guard !request.texts.isEmpty else { return [] }
        let config = try resolvedConfig()
        let prompt = TranslationBatchPrompt.build(
            texts: request.texts,
            targetLanguage: request.targetLanguage,
            context: request.context
        )
        let urlRequest = try makeRequest(config: config, prompt: prompt)
        let data = try await perform(request: urlRequest)
        let content = try Self.extractContent(from: data, decoder: decoder)
        return try TranslationBatchResponse.parse(content, expectedCount: request.texts.count)
    }
    // MARK: - Prompt

    static func buildPrompt(
        text: String,
        targetLanguage: String,
        context: TranslationContext?
    ) -> String {
        let target = TranslationTargetLanguageCatalog.language(for: targetLanguage).promptName
        if let context, !context.isEmpty {
            return """
            以下是最近的剧情字幕上下文，用于保持翻译连贯：
            \(context.text)

            请把下面这行字幕翻译成\(target)。只输出译文，不要加引号或解释：
            \(text)
            """
        }
        return "请把下面这行字幕翻译成\(target)。只输出译文，不要加引号或解释：\n\(text)"
    }

    // MARK: - 请求

    private struct CloudConfig: Sendable {
        let endpointURL: URL
        let apiKey: String
        let modelName: String
    }

    private func resolvedConfig() throws -> CloudConfig {
        let rawBase = settings.cloudBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBase.isEmpty, let base = URL(string: rawBase) else {
            throw CloudLLMError.invalidBaseURL
        }
        guard let apiKey = try apiKeyStore.loadAPIKey(), !apiKey.isEmpty else {
            throw CloudLLMError.emptyAPIKey
        }
        let modelName = settings.cloudModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw CloudLLMError.emptyModelName
        }
        // 规范化 Base URL：去掉末尾斜杠，必要时补 /chat/completions。
        var normalized = base.absoluteString
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        let endpoint = normalized.hasSuffix("/chat/completions")
            ? normalized
            : normalized + "/chat/completions"
        guard let endpointURL = URL(string: endpoint) else {
            throw CloudLLMError.invalidBaseURL
        }
        return CloudConfig(endpointURL: endpointURL, apiKey: apiKey, modelName: modelName)
    }

    private func makeRequest(config: CloudConfig, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: config.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let body: [String: any Sendable] = [
            "model": config.modelName,
            "messages": [
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.0,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func perform(request: URLRequest) async throws -> Data {
        // 兜底：请求期间申请后台任务，短暂锁屏 / 后台时也能尽量完成。
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TranslationRequest")
        defer { UIApplication.shared.endBackgroundTask(backgroundTaskID) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CloudLLMError.networkError(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw CloudLLMError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudLLMError.httpError(
                statusCode: http.statusCode,
                message: Self.errorMessage(from: data)
            )
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? "未知错误"
    }

    private static func extractContent(from data: Data, decoder: JSONDecoder) throws -> String {
        let decoded: ChatCompletionResponse
        do {
            decoded = try decoder.decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw CloudLLMError.invalidResponse
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw CloudLLMError.emptyContent
        }
        return content
    }
}

// MARK: - OpenAI 兼容响应模型

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatCompletionChoice]
}

private struct ChatCompletionChoice: Decodable {
    let message: ChatCompletionMessage
}

private struct ChatCompletionMessage: Decodable {
    let content: String
}

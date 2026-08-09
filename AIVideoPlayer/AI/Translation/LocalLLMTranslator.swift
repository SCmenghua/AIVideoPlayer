import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers

/// 本地 LLM Provider（MLX Swift + Gemma 4 E2B 4-bit）。
/// 模型按需下载（`LocalModelDownloadManager`），下载完成后加载推理，完全离线。
@MainActor
public final class LocalLLMTranslator: TranslationEngine {
    public var providerID: TranslationProviderID { .localLLM }
    public var displayName: String { TranslationProviderCatalog.localLLM.displayName }
    public var isFullyLocal: Bool { true }
    public var supportsContextPolish: Bool { true }

    public var isReady: Bool {
        isModelDownloaded && !isModelLoading && container != nil
    }

    public var isModelDownloaded: Bool {
        LocalModelStorage.isDownloaded(
            modelDescriptor.id, files: modelDescriptor.requiredFiles
        )
    }

    public private(set) var isModelLoading = false

    private let modelDescriptor: LocalModelDescriptor
    private let tokenizerLoader: any TokenizerLoader
    private var container: ModelContainer?
    private var chatSession: ChatSession?
    private var loadTask: Task<ModelContainer, Error>?

    public init(
        modelDescriptor: LocalModelDescriptor,
        tokenizerLoader: any TokenizerLoader = SwiftTransformersTokenizerLoader()
    ) {
        self.modelDescriptor = modelDescriptor
        self.tokenizerLoader = tokenizerLoader
        // 引用官方注册表配置，确保 MLXLLM 的模型工厂随模块注册（NSClassFromString 动态查找）。
        _ = LLMRegistry.gemma4_e2b_it_4bit
    }

    public func translate(
        _ text: String,
        from sourceLanguage: String?,
        to targetLanguage: String,
        context: TranslationContext?
    ) async throws -> String {
        let session = try await ensureLoaded()
        let prompt = Self.buildPrompt(
            text: text,
            targetLanguage: targetLanguage,
            context: context
        )
        return try await session.respond(to: prompt)
    }

    // MARK: - 模型加载

    private func ensureLoaded() async throws -> ChatSession {
        if let chatSession { return chatSession }
        if let loadTask { return try await waitForLoad(loadTask) }
        guard isModelDownloaded else {
            throw LocalLLMError.modelNotDownloaded
        }
        isModelLoading = true
        let directory = LocalModelStorage.directory(for: modelDescriptor.id)
        let loader = tokenizerLoader
        let task = Task<ModelContainer, Error> {
            try await loadModelContainer(from: directory, using: loader)
        }
        loadTask = task
        return try await waitForLoad(task)
    }

    private func waitForLoad(_ task: Task<ModelContainer, Error>) async throws -> ChatSession {
        defer { loadTask = nil }
        do {
            let loaded = try await task.value
            container = loaded
            let session = ChatSession(loaded, instructions: Self.systemInstructions)
            chatSession = session
            isModelLoading = false
            return session
        } catch {
            isModelLoading = false
            throw error
        }
    }

    // MARK: - Prompt

    nonisolated private static let systemInstructions = """
    你是专业影视字幕翻译。把用户给的字幕翻译成目标语言，保持语气、长度和口语风格；只输出译文本身，不要加引号或解释。
    """

    static func buildPrompt(
        text: String,
        targetLanguage: String,
        context: TranslationContext?
    ) -> String {
        let target = TranslationTargetLanguageCatalog.language(for: targetLanguage).promptName
        if let context, !context.isEmpty {
            return """
            最近的剧情上下文（保持翻译连贯）：
            \(context.text)

            翻译下面这行字幕为 \(target)。只输出译文：
            \(text)
            """
        }
        return "翻译下面这行字幕为 \(target)。只输出译文：\n\(text)"
    }
}

/// 本地 LLM 错误。
public enum LocalLLMError: LocalizedError, Sendable {
    case modelNotDownloaded
    case modelNotLoaded
    case modelLoadFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            "本地大模型尚未下载，请先在设置中下载。"
        case .modelNotLoaded:
            "本地大模型未加载。"
        case .modelLoadFailed:
            "本地大模型加载失败，请重试。"
        }
    }
}

/// 把 swift-transformers 的 Tokenizer 加载为 MLXLMCommon.Tokenizer。
public struct SwiftTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader, Sendable {
    public init() {}

    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizersAdapter(tokenizer: tokenizer)
    }
}

/// Tokenizers → MLXLMCommon.Tokenizer 适配器。
public struct TokenizersAdapter: MLXLMCommon.Tokenizer, Sendable {
    private let upstream: any Tokenizers.Tokenizer

    public init(tokenizer: any Tokenizers.Tokenizer) {
        self.upstream = tokenizer
    }

    public func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    public func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    public func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    public func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    public var bosToken: String? { upstream.bosToken }
    public var eosToken: String? { upstream.eosToken }
    public var unknownToken: String? { upstream.unknownToken }

    public func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }
}

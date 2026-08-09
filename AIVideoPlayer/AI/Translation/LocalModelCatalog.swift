import Foundation

/// 本地 LLM 模型描述（Phase 7 提供 Gemma 4 E2B；后续可扩展更多模型）。
public struct LocalModelDescriptor: Sendable, Hashable {
    /// Hugging Face 仓库 ID。
    public let id: String
    public let displayName: String
    public let sizeLabel: String
    /// 需要下载的文件（相对仓库根目录）。
    public let requiredFiles: [String]
    /// 模型额外的 EOS 标记。
    public let extraEOSTokens: Set<String>

    public init(
        id: String,
        displayName: String,
        sizeLabel: String,
        requiredFiles: [String],
        extraEOSTokens: Set<String>
    ) {
        self.id = id
        self.displayName = displayName
        self.sizeLabel = sizeLabel
        self.requiredFiles = requiredFiles
        self.extraEOSTokens = extraEOSTokens
    }
}

public enum LocalModelCatalog {
    /// Gemma 4 E2B 4-bit（MLX 社区转换；`LLMRegistry.gemma4_e2b_it_4bit`）。
    public static let gemma4E2B = LocalModelDescriptor(
        id: "mlx-community/gemma-4-e2b-it-4bit",
        displayName: "Gemma 4 E2B（4-bit）",
        sizeLabel: "约 3.5 GB",
        requiredFiles: [
            "config.json",
            "generation_config.json",
            "model.safetensors",
            "model.safetensors.index.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "chat_template.jinja",
        ],
        extraEOSTokens: ["<turn|>"]
    )

    public static let all: [LocalModelDescriptor] = [gemma4E2B]

    public static func descriptor(for id: String) -> LocalModelDescriptor? {
        all.first { $0.id == id }
    }
}

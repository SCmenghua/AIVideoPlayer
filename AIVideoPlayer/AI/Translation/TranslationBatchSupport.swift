import Foundation

/// 批量翻译提示词构建（Phase 9.3.1）。
/// 通过 JSON 数组约束 LLM 输出，保证「N 进 N 出」以便按顺序回填字幕时间轴。
public enum TranslationBatchPrompt {
    public static func build(
        texts: [String],
        targetLanguage: String,
        context: TranslationContext?
    ) -> String {
        let target = TranslationTargetLanguageCatalog.language(for: targetLanguage).promptName
        var prompt = ""
        if let context, !context.isEmpty {
            prompt += "最近的剧情字幕上下文（用于保持翻译连贯）：\n\(context.text)\n\n"
        }
        prompt += "请把下面 \(texts.count) 条字幕逐条翻译成\(target)。\n"
        prompt += "要求：只输出一个 JSON 字符串数组，数组长度必须为 \(texts.count)，"
        prompt += "第 i 个元素对应第 i 条字幕的译文；不要输出任何解释或多余文字。\n\n"
        prompt += texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return prompt
    }
}

/// 批量翻译响应解析（Phase 9.3.1）。
public enum TranslationBatchResponse {
    public static func parse(_ raw: String, expectedCount: Int) throws -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationBatchError.emptyResponse
        }
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return try validate(array, expectedCount: expectedCount)
        }
        let lines = trimmed
            .split(separator: "\n")
            .map { Self.cleanLine(String($0)) }
            .filter { !$0.isEmpty }
        return try validate(lines, expectedCount: expectedCount)
    }

    private static func validate(_ items: [String], expectedCount: Int) throws -> [String] {
        guard items.count == expectedCount else {
            throw TranslationBatchError.mismatchedCount(
                expected: expectedCount,
                actual: items.count
            )
        }
        return items
    }

    private static func cleanLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = text.firstIndex(of: ".") {
            let prefix = text[..<dot]
            if !prefix.isEmpty && prefix.allSatisfy({ $0.isNumber || $0 == " " }) {
                text = String(text[text.index(after: dot)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if text.hasPrefix("- ") {
            text = String(text.dropFirst(2))
        }
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 批量翻译错误（Phase 9.3.1）。
public enum TranslationBatchError: LocalizedError, Sendable, Equatable {
    case emptyResponse
    case mismatchedCount(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            "大模型返回了空内容。"
        case .mismatchedCount(let expected, let actual):
            "大模型返回的译文字幕数量不一致（期望 \(expected) 条，实际 \(actual) 条）。"
        }
    }
}
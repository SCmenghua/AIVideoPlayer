import Foundation

/// 剧情理解润色的上下文管理器：维护最近的字幕历史并压缩为小段上下文
/// （禁止把大段原始字幕直接塞进请求）。
@MainActor
public final class TranslationContextProvider {
    public struct Entry: Sendable, Equatable {
        public let originalText: String
        public let translatedText: String

        public init(originalText: String, translatedText: String) {
            self.originalText = originalText
            self.translatedText = translatedText
        }
    }

    public private(set) var recentEntries: [Entry] = []

    public let maxEntries: Int
    public let maxCharactersPerEntry: Int
    public let maxTotalCharacters: Int

    public init(
        maxEntries: Int = 10,
        maxCharactersPerEntry: Int = 160,
        maxTotalCharacters: Int = 1200
    ) {
        self.maxEntries = maxEntries
        self.maxCharactersPerEntry = maxCharactersPerEntry
        self.maxTotalCharacters = maxTotalCharacters
    }

    public var hasRecentEntries: Bool { !recentEntries.isEmpty }

    /// 记录一条已翻译完成的字幕（只保留最近 `maxEntries` 条）。
    public func record(original: String, translated: String) {
        recentEntries.append(Entry(originalText: original, translatedText: translated))
        if recentEntries.count > maxEntries {
            recentEntries.removeFirst(recentEntries.count - maxEntries)
        }
    }

    /// 生成压缩后的上下文：逐条截断、优先保留更近的条目、总字符数受预算约束。
    public func makeContext() -> TranslationContext {
        var parts: [String] = []
        var used = 0
        for entry in recentEntries.reversed() {
            let line = Self.compressedLine(entry, limit: maxCharactersPerEntry)
            if used + line.count > maxTotalCharacters {
                if parts.isEmpty {
                    parts.append(line)
                }
                break
            }
            parts.append(line)
            used += line.count
        }
        return TranslationContext(text: parts.reversed().joined(separator: "\n"))
    }

    public func reset() {
        recentEntries.removeAll(keepingCapacity: true)
    }

    private static func compressedLine(_ entry: Entry, limit: Int) -> String {
        let original = truncate(entry.originalText, to: limit / 2)
        let translated = truncate(entry.translatedText, to: limit / 2)
        return truncate("\(original) → \(translated)", to: limit)
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}

import Foundation

/// 合并 Whisper 在同一识别窗口内切开的连续 final 段，给翻译器更完整的句子上下文。
/// partial 保持原样，以免牺牲实时预览的响应速度。
public enum SubtitleSegmentMerger {
    /// 合并后的最长时间轴跨度，避免一句过长影响字幕阅读节奏。
    public static let maximumDuration: TimeInterval = 8
    /// 合并后的最大字符数，避免无标点的长独白无限累积。
    public static let maximumCharacterCount = 120
    private static let maximumGap: TimeInterval = 0.5

    public static func mergeFinalSegments(_ segments: [SubtitleSegment]) -> [SubtitleSegment] {
        var merged: [SubtitleSegment] = []

        for segment in segments {
            guard !segment.isPartial else {
                merged.append(segment)
                continue
            }

            guard let previous = merged.last,
                  !previous.isPartial,
                  shouldMerge(previous, with: segment)
            else {
                merged.append(segment)
                continue
            }

            merged[merged.count - 1] = merge(previous, with: segment)
        }

        return merged
    }

    private static func shouldMerge(_ previous: SubtitleSegment, with next: SubtitleSegment) -> Bool {
        let gap = next.startTime - previous.endTime
        let combinedDuration = next.endTime - previous.startTime
        let combinedText = join(previous.originalText, next.originalText)

        return gap >= -maximumGap
            && gap <= maximumGap
            && !endsSentence(previous.originalText)
            && combinedDuration <= maximumDuration
            && combinedText.count <= maximumCharacterCount
    }

    private static func merge(_ previous: SubtitleSegment, with next: SubtitleSegment) -> SubtitleSegment {
        SubtitleSegment(
            id: previous.id,
            startTime: previous.startTime,
            endTime: max(previous.endTime, next.endTime),
            originalText: join(previous.originalText, next.originalText),
            confidence: min(previous.confidence, next.confidence),
            isPartial: false
        )
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last else {
            return false
        }
        return ".!?。！？".unicodeScalars.contains(last)
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }

        let needsSpace = !containsCJK(lhs) && !containsCJK(rhs)
        return needsSpace ? "\(lhs) \(rhs)" : "\(lhs)\(rhs)"
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value)
                || (0x3400...0x9FFF).contains($0.value)
                || (0xAC00...0xD7AF).contains($0.value)
        }
    }
}

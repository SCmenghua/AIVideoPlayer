import Foundation

/// AI 字幕流水线产出的一条字幕。
/// `isPartial` 区分实时识别中间结果与最终结果。
public struct SubtitleSegment: Identifiable, Hashable, Sendable, Codable {
    /// 片段最小可显示时长（秒）：时间戳缺失 / 异常（end <= start）时的兜底显示窗口，
    /// 避免零时长片段永远无法命中播放光标导致字幕不显示。
    public static let minimumDisplayDuration: TimeInterval = 0.5

    public let id: UUID
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let originalText: String
    public var translatedText: String?
    public let confidence: Double
    public let isPartial: Bool

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        originalText: String,
        translatedText: String? = nil,
        confidence: Double,
        isPartial: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.translatedText = translatedText
        self.confidence = confidence
        self.isPartial = isPartial
    }
}

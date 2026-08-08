import Foundation

/// AI 字幕流水线产出的一条字幕。
/// `isPartial` 区分实时识别中间结果与最终结果。
public struct SubtitleSegment: Identifiable, Hashable, Sendable, Codable {
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

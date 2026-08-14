import Foundation

/// Rejects weak and rapidly repeated final transcriptions before they reach the subtitle history.
/// The gate intentionally has no language or phrase-specific rules.
struct SpeechRecognitionQualityGate: Sendable {
    struct Configuration: Sendable {
        let minimumConfidence: Double
        let repeatedTextInterval: TimeInterval

        init(
            minimumConfidence: Double = 0.12,
            repeatedTextInterval: TimeInterval = 8
        ) {
            self.minimumConfidence = minimumConfidence
            self.repeatedTextInterval = repeatedTextInterval
        }
    }

    enum RejectionReason: Sendable, Equatable {
        case lowConfidence
        case repeatedText
    }

    private struct RecentFinal: Sendable {
        let normalizedText: String
        let startTime: TimeInterval
    }

    private let configuration: Configuration
    private var recentFinals: [RecentFinal] = []

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func rejectionReason(for segment: SubtitleSegment) -> RejectionReason? {
        guard segment.confidence >= configuration.minimumConfidence else {
            return .lowConfidence
        }

        let normalizedText = Self.normalizedText(segment.originalText)
        guard !normalizedText.isEmpty else { return .lowConfidence }

        recentFinals.removeAll {
            segment.startTime - $0.startTime > configuration.repeatedTextInterval
        }
        if recentFinals.contains(where: {
            $0.normalizedText == normalizedText
                && segment.startTime >= $0.startTime
                && segment.startTime - $0.startTime <= configuration.repeatedTextInterval
        }) {
            return .repeatedText
        }

        recentFinals.append(RecentFinal(normalizedText: normalizedText, startTime: segment.startTime))
        return nil
    }

    mutating func reset() {
        recentFinals.removeAll(keepingCapacity: true)
    }

    static func normalizedText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters)
                .union(.symbols))
            .joined()
    }
}

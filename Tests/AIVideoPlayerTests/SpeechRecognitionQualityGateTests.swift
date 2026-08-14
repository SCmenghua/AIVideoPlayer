import Foundation
import Testing
@testable import AIVideoPlayer

struct SpeechRecognitionQualityGateTests {
    @Test func acceptsNormalFinalAndRejectsImmediateDuplicate() {
        var gate = SpeechRecognitionQualityGate()

        #expect(gate.rejectionReason(for: segment(text: "ご視聴ありがとうございました", start: 0, confidence: 0.9)) == nil)
        #expect(
            gate.rejectionReason(for: segment(text: "ご 視聴ありがとうございました！", start: 5, confidence: 0.9))
                == .repeatedText
        )
    }

    @Test func allowsSameTextAfterSuppressionInterval() {
        var gate = SpeechRecognitionQualityGate()

        #expect(gate.rejectionReason(for: segment(text: "hello", start: 0, confidence: 0.9)) == nil)
        #expect(gate.rejectionReason(for: segment(text: "hello", start: 9, confidence: 0.9)) == nil)
    }

    @Test func rejectsLowConfidenceFinal() {
        var gate = SpeechRecognitionQualityGate()

        #expect(gate.rejectionReason(for: segment(text: "uncertain", start: 0, confidence: 0.11)) == .lowConfidence)
    }

    @Test func resetAllowsTextForNewRecognitionSession() {
        var gate = SpeechRecognitionQualityGate()

        #expect(gate.rejectionReason(for: segment(text: "hello", start: 10, confidence: 0.9)) == nil)
        gate.reset()
        #expect(gate.rejectionReason(for: segment(text: "hello", start: 10, confidence: 0.9)) == nil)
    }

    private func segment(text: String, start: TimeInterval, confidence: Double) -> SubtitleSegment {
        SubtitleSegment(
            startTime: start,
            endTime: start + 1,
            originalText: text,
            confidence: confidence,
            isPartial: false
        )
    }
}

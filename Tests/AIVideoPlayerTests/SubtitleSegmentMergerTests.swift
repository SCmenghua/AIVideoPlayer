import Foundation
import Testing
@testable import AIVideoPlayer

struct SubtitleSegmentMergerTests {

    @Test func mergesAdjacentEnglishFragmentsWithoutTerminalPunctuation() {
        let merged = SubtitleSegmentMerger.mergeFinalSegments([
            segment(start: 0, end: 1, text: "I think"),
            segment(start: 1, end: 2, text: "this is actually"),
            segment(start: 2, end: 3, text: "a very important"),
            segment(start: 3, end: 4, text: "point.")
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.startTime == 0)
        #expect(merged.first?.endTime == 4)
        #expect(merged.first?.originalText == "I think this is actually a very important point.")
    }

    @Test func keepsSentenceBoundaryAsSeparateTranslationUnit() {
        let merged = SubtitleSegmentMerger.mergeFinalSegments([
            segment(start: 0, end: 1, text: "First point."),
            segment(start: 1.1, end: 2, text: "Second point")
        ])

        #expect(merged.count == 2)
        #expect(merged[0].originalText == "First point.")
        #expect(merged[1].originalText == "Second point")
    }

    @Test func joinsJapaneseWithoutArtificialSpace() {
        let merged = SubtitleSegmentMerger.mergeFinalSegments([
            segment(start: 0, end: 1, text: "これは"),
            segment(start: 1, end: 2, text: "大事な"),
            segment(start: 2, end: 3, text: "話です。")
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.originalText == "これは大事な話です。")
    }

    @Test func doesNotMergePartialSegments() {
        let partial = SubtitleSegment(
            startTime: 0,
            endTime: 1,
            originalText: "I think",
            confidence: 0.5,
            isPartial: true
        )
        let merged = SubtitleSegmentMerger.mergeFinalSegments([
            partial,
            segment(start: 1, end: 2, text: "this matters")
        ])

        #expect(merged.count == 2)
        #expect(merged[0].isPartial)
    }

    @Test func limitsUnpunctuatedSegmentDuration() {
        let merged = SubtitleSegmentMerger.mergeFinalSegments([
            segment(start: 0, end: 4, text: "First part"),
            segment(start: 4, end: 8, text: "second part"),
            segment(start: 8, end: 9, text: "third part")
        ])

        #expect(merged.count == 2)
        #expect(merged[0].originalText == "First part second part")
        #expect(merged[1].originalText == "third part")
    }

    private func segment(start: TimeInterval, end: TimeInterval, text: String) -> SubtitleSegment {
        SubtitleSegment(
            startTime: start,
            endTime: end,
            originalText: text,
            confidence: 0.9,
            isPartial: false
        )
    }
}

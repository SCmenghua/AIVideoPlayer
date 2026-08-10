import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleTranscriptStoreTests {

    @Test func segmentAtReturnsWholeSentenceAlignedToPlaybackCursor() {
        let store = SubtitleTranscriptStore()
        let sentence = makeSegment(start: 10, end: 14, text: "整句")
        store.append(sentence)

        #expect(store.segment(at: 9.999) == nil)
        #expect(store.segment(at: 10) == sentence)
        #expect(store.segment(at: 13.999) == sentence)
        #expect(store.segment(at: 14) == nil)
    }

    @Test func finalPreferredOverOverlappingPartial() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 5, end: 8, text: "hi", isPartial: true))
        store.append(makeSegment(start: 5.2, end: 7.5, text: "hello"))

        #expect(store.segment(at: 6)?.originalText == "hello")
        #expect(store.segment(at: 6)?.isPartial == false)
    }

    @Test func appendFinalPrunesOverlappingPartials() {
        let store = SubtitleTranscriptStore()
        let partial = makeSegment(start: 5, end: 8, text: "hi", isPartial: true)
        let final = makeSegment(start: 5.2, end: 7.5, text: "hello")
        store.append(partial)
        #expect(store.segments.count == 1)

        store.append(final)
        #expect(store.segments == [final])
    }

    @Test func partialsOutsideFinalRangeAreKept() {
        let store = SubtitleTranscriptStore()
        let partial = makeSegment(start: 1, end: 3, text: "early", isPartial: true)
        let final = makeSegment(start: 5, end: 7, text: "late")
        store.append(partial)
        store.append(final)

        #expect(store.segments.count == 2)
        #expect(store.segment(at: 2)?.originalText == "early")
    }

    @Test func latestPartialWinsAmongOverlappingPartials() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 5, end: 8, text: "old", isPartial: true))
        store.append(makeSegment(start: 5, end: 8, text: "new", isPartial: true))

        #expect(store.segment(at: 6)?.originalText == "new")
    }

    @Test func clearRemovesAllSegments() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 0, end: 1))
        store.append(makeSegment(start: 2, end: 3))

        store.clear()

        #expect(store.segments.isEmpty)
        #expect(store.segment(at: 0.5) == nil)
    }

    @Test func storeCapsMemoryAndKeepsNewest() {
        let store = SubtitleTranscriptStore()
        for index in 0..<300 {
            store.append(makeSegment(start: Double(index), end: Double(index) + 1, text: "\(index)"))
        }

        #expect(store.segments.count <= SubtitleTranscriptStore.maxStoredSegments)
        #expect(store.segment(at: 299.5)?.originalText == "299")
        #expect(store.segment(at: 0.5) == nil)
    }

    @Test func storeStaysSortedAfterOutOfOrderAppend() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 5, end: 6))
        store.append(makeSegment(start: 1, end: 2))
        store.append(makeSegment(start: 3, end: 4))

        #expect(store.segments.map(\.startTime) == [1, 3, 5])
    }

    // MARK: - 辅助

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        text: String = "hello",
        isPartial: Bool = false
    ) -> SubtitleSegment {
        SubtitleSegment(
            startTime: start,
            endTime: end,
            originalText: text,
            confidence: 0.9,
            isPartial: isPartial
        )
    }
}

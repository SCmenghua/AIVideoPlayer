import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleTimelineTests {

    @Test func segmentAtReturnsWholeSentenceAlignedToPlaybackCursor() async {
        let timeline = SubtitleTimeline()
        let sentence = makeSegment(start: 10, end: 14, text: "整句")
        await timeline.append(sentence)

        #expect(timeline.segment(at: 9.999) == nil)
        #expect(timeline.segment(at: 10) == sentence)
        #expect(timeline.segment(at: 13.999) == sentence)
        #expect(timeline.segment(at: 14) == nil)
    }

    @Test func finalPreferredOverOverlappingPartial() async {
        let timeline = SubtitleTimeline()
        await timeline.append(makeSegment(start: 5, end: 8, text: "hi", isPartial: true))
        await timeline.append(makeSegment(start: 5.2, end: 7.5, text: "hello"))

        #expect(timeline.segment(at: 6)?.originalText == "hello")
        #expect(timeline.segment(at: 6)?.isPartial == false)
    }

    @Test func appendFinalPrunesOverlappingPartials() async {
        let timeline = SubtitleTimeline()
        let partial = makeSegment(start: 5, end: 8, text: "hi", isPartial: true)
        let final = makeSegment(start: 5.2, end: 7.5, text: "hello")
        await timeline.append(partial)
        #expect(timeline.segments.count == 1)

        await timeline.append(final)
        #expect(timeline.segments == [final])
    }

    @Test func partialsOutsideFinalRangeAreKept() async {
        let timeline = SubtitleTimeline()
        let partial = makeSegment(start: 1, end: 3, text: "early", isPartial: true)
        let final = makeSegment(start: 5, end: 7, text: "late")
        await timeline.append(partial)
        await timeline.append(final)

        #expect(timeline.segments.count == 2)
        #expect(timeline.segment(at: 2)?.originalText == "early")
    }

    @Test func updateReplacesSegmentById() async {
        let timeline = SubtitleTimeline()
        let original = makeSegment(start: 5, end: 8, text: "a")
        await timeline.append(original)

        let updated = SubtitleSegment(
            id: original.id,
            startTime: 6,
            endTime: 9,
            originalText: "b",
            confidence: 0.9
        )
        await timeline.update(updated)

        #expect(timeline.segments.count == 1)
        #expect(timeline.segment(at: 7) == updated)
        #expect(timeline.segment(at: 5) == nil)
    }

    @Test func removeAllClearsTimeline() async {
        let timeline = SubtitleTimeline()
        await timeline.append(makeSegment(start: 0, end: 1))
        await timeline.append(makeSegment(start: 2, end: 3))

        await timeline.removeAll()

        #expect(timeline.segments.isEmpty)
        #expect(timeline.segment(at: 0.5) == nil)
    }

    @Test func timelineCapsMemoryAndKeepsNewest() async {
        let timeline = SubtitleTimeline()
        for index in 0..<600 {
            await timeline.append(makeSegment(start: Double(index), end: Double(index) + 1, text: "\(index)"))
        }

        #expect(timeline.segments.count <= 500)
        #expect(timeline.segment(at: 599.5)?.originalText == "599")
        #expect(timeline.segment(at: 0.5) == nil)
    }

    @Test func timelineStaysSortedAfterOutOfOrderAppend() async {
        let timeline = SubtitleTimeline()
        await timeline.append(makeSegment(start: 5, end: 6))
        await timeline.append(makeSegment(start: 1, end: 2))
        await timeline.append(makeSegment(start: 3, end: 4))

        #expect(timeline.segments.map(\.startTime) == [1, 3, 5])
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

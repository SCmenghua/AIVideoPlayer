import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct SubtitleTranscriptStoreTests {

    @Test func segmentAtReturnsWholeSentenceAlignedToPlaybackCursor() {
        let store = SubtitleTranscriptStore()
        let sentence = makeSegment(start: 10, end: 14, text: "整句")
        store.append(sentence)
        store.flush()  // 立即刷新以便测试

        #expect(store.segment(at: 9.999) == nil)
        #expect(store.segment(at: 10) == sentence)
        #expect(store.segment(at: 13.999) == sentence)
        #expect(store.segment(at: 14) == nil)
    }

    @Test func finalPreferredOverOverlappingPartial() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 5, end: 8, text: "hi", isPartial: true))
        store.append(makeSegment(start: 5.2, end: 7.5, text: "hello"))
        store.flush()  // 立即刷新以便测试

        #expect(store.segment(at: 6)?.originalText == "hello")
        #expect(store.segment(at: 6)?.isPartial == false)
    }

    @Test func appendFinalPrunesOverlappingPartials() {
        let store = SubtitleTranscriptStore()
        let partial = makeSegment(start: 5, end: 8, text: "hi", isPartial: true)
        let final = makeSegment(start: 5.2, end: 7.5, text: "hello")
        store.append(partial)
        store.flush()
        #expect(store.segments.isEmpty)
        #expect(store.previewSegment == partial)

        store.append(final)
        store.flush()
        #expect(store.segments == [final])
        #expect(store.previewSegment == nil)
    }

    @Test func partialsOutsideFinalRangeAreKept() {
        let store = SubtitleTranscriptStore()
        let partial = makeSegment(start: 1, end: 3, text: "early", isPartial: true)
        let final = makeSegment(start: 5, end: 7, text: "late")
        store.append(partial)
        store.append(final)
        store.flush()

        #expect(store.segments == [final])
        #expect(store.previewSegment == partial)
        #expect(store.segment(at: 2)?.originalText == "early")
    }

    @Test func latestPartialWinsAmongOverlappingPartials() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 5, end: 8, text: "old", isPartial: true))
        store.append(makeSegment(start: 5, end: 8, text: "new", isPartial: true))
        store.flush()

        #expect(store.segments.isEmpty)
        #expect(store.previewSegment?.originalText == "new")
        #expect(store.segment(at: 6)?.originalText == "new")
    }

    @Test func clearRemovesAllSegments() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 0, end: 1))
        store.append(makeSegment(start: 2, end: 3))
        store.flush()

        store.clear()

        #expect(store.segments.isEmpty)
        #expect(store.previewSegment == nil)
        #expect(store.segment(at: 0.5) == nil)
    }

    @Test func zeroDurationSegmentStillMatchesPlaybackCursor() {
        let store = SubtitleTranscriptStore()
        // 时间戳异常（end == start）的 final 按最小可显示时长兜底，
        // 避免「翻译已产出但字幕不显示」。
        store.append(
            SubtitleSegment(
                startTime: 10,
                endTime: 10,
                originalText: "零时长",
                confidence: 0.9,
                isPartial: false
            )
        )
        store.flush()

        #expect(store.segment(at: 10)?.originalText == "零时长")
        #expect(store.segment(at: 10.4)?.originalText == "零时长")
        #expect(store.segment(at: 10.6) == nil)
    }

    @Test func storeCapsMemoryAndKeepsNewest() {
        let store = SubtitleTranscriptStore()
        for index in 0..<300 {
            store.append(makeSegment(start: Double(index), end: Double(index) + 1, text: "\(index)"))
        }
        store.flush()

        #expect(store.segments.count <= SubtitleTranscriptStore.maxStoredSegments)
        #expect(store.segment(at: 299.5)?.originalText == "299")
        #expect(store.segment(at: 0.5) == nil)
    }

    @Test func storeStaysSortedAfterOutOfOrderAppend() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 5, end: 6))
        store.append(makeSegment(start: 1, end: 2))
        store.append(makeSegment(start: 3, end: 4))
        store.flush()

        #expect(store.segments.map(\.startTime) == [1, 3, 5])
    }

    @Test func batchUpdateReducesUIRefreshFrequency() async {
        let store = SubtitleTranscriptStore()
        // 快速追加多条字幕，验证不会立即触发 UI 刷新
        for index in 0..<10 {
            store.append(makeSegment(start: Double(index), end: Double(index) + 1, text: "\(index)"))
        }
        // 此时 segments 应该还是空的（或只有少量已刷新的）
        let countBeforeFlush = store.segments.count
        #expect(countBeforeFlush < 10)

        // 手动刷新后全部可见
        store.flush()
        #expect(store.segments.count == 10)
    }

    @Test func segmentAtAutoFlushesForLatestResults() {
        let store = SubtitleTranscriptStore()
        store.append(makeSegment(start: 1, end: 2, text: "auto"))
        // segment(at:) 会自动刷新，确保最新结果立即可见
        #expect(store.segment(at: 1.5)?.originalText == "auto")
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

import Foundation
import Testing
@testable import AIVideoPlayer

struct PCMBufferTests {

    @Test func appendTracksCapturedEnd() {
        let buffer = PCMBuffer()
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, startTime: 0))
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, startTime: 1))

        #expect(buffer.captureStart == 0)
        #expect(buffer.capturedEnd == 2)
        #expect(buffer.sampleRateValue == 16_000)
    }

    @Test func extractReturnsOnlyFullyBufferedRanges() {
        let buffer = PCMBuffer()
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 32_000), sampleRate: 16_000, startTime: 0))

        #expect(buffer.extract(from: 0, to: 2)?.count == 32_000)
        #expect(buffer.extract(from: 0.5, to: 1.5)?.count == 16_000)
        #expect(buffer.extract(from: 0, to: 3) == nil)
        #expect(buffer.extract(from: 2, to: 3) == nil)
    }

    @Test func resetRebasesTimeline() {
        let buffer = PCMBuffer()
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, startTime: 0))
        buffer.reset(to: 42)

        #expect(buffer.capturedEnd == 42)
        #expect(buffer.extract(from: 0, to: 1) == nil)

        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, startTime: 42))
        #expect(buffer.extract(from: 42, to: 43)?.count == 16_000)
    }

    @Test func ignoresStaleChunksAfterSeek() {
        let buffer = PCMBuffer()
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, startTime: 0))
        buffer.reset(to: 10)
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, startTime: 5))

        #expect(buffer.capturedEnd == 11)
    }

    @Test func discardTrimsFrontAndKeepsTimeline() {
        let buffer = PCMBuffer()
        buffer.append(PCMChunk(samples: [Float](repeating: 0, count: 32_000), sampleRate: 16_000, startTime: 0))
        buffer.discard(before: 1)

        #expect(buffer.captureStart == 1)
        #expect(buffer.capturedEnd == 2)
        #expect(buffer.extract(from: 1, to: 2)?.count == 16_000)
    }
}

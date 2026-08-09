import Foundation
import Testing
@testable import AIVideoPlayer

struct ModelsTests {

    @Test func remoteFilePlayability() throws {
        let video = try makeRemoteFile(kind: .video)
        #expect(video.isPlayable)

        let audio = try makeRemoteFile(kind: .audio)
        #expect(audio.isPlayable)

        let folder = try makeRemoteFile(kind: .folder)
        #expect(!folder.isPlayable)
    }

    @Test func subtitleSegmentRoundTrip() throws {
        let segment = SubtitleSegment(
            startTime: 1.0,
            endTime: 2.5,
            originalText: "Hello",
            translatedText: "你好",
            confidence: 0.95,
            isPartial: false
        )

        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(SubtitleSegment.self, from: data)

        #expect(decoded == segment)
    }

    @Test func aiStateCoversFullPipeline() {
        #expect(AIState.allCases.count == 7)
        #expect(AIState.allCases.contains(.transcribing))
        #expect(AIState.allCases.contains(.translating))
        #expect(AIState.allCases.contains(.error))
    }

    @Test func loadStateExplicitLifecycle() {
        #expect(LoadState<String>.loading != LoadState<String>.ready("x"))
        #expect(LoadState<String>.ready("x") == LoadState<String>.ready("x"))
        #expect(LoadState<String>.cancelled == LoadState<String>.cancelled)
        #expect(LoadState<String>.empty != LoadState<String>.error("boom"))
    }

    @Test func mediaItemCodable() throws {
        let item = MockRemoteFiles.sampleMediaItem
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)

        #expect(decoded == item)
        #expect(decoded.kind == .video)
        #expect(decoded.source == .remote)
    }

    @Test func remoteFileInfersHLSAsVideo() throws {
        let m3u8 = try #require(URL(string: "https://example.com/stream.m3u8"))
        #expect(RemoteFile.Kind.infer(isCollection: false, url: m3u8) == .video)

        let m3u = try #require(URL(string: "https://example.com/playlist.m3u"))
        #expect(RemoteFile.Kind.infer(isCollection: false, url: m3u) == .video)
    }

    private func makeRemoteFile(kind: RemoteFile.Kind) throws -> RemoteFile {
        let url = try #require(URL(string: "https://example.com/sample"))
        return RemoteFile(
            name: "Sample",
            url: url,
            kind: kind,
            connection: .webdav
        )
    }
}

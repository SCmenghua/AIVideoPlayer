import Foundation
import Testing
@testable import AIVideoPlayer

/// Phase 4：`WebMediaExtractor` 行为测试。
/// 覆盖直链媒体、HLS、HTML5 video 提取、相对地址解析、去重、DRM 跳过、错误与取消。
@Suite(.serialized)
struct WebMediaExtractorTests {

    // MARK: - 直链媒体

    @Test func directMP4ReturnsSingleVideoItem() async throws {
        let url = try #require(URL(string: "https://example.com/movies/big.mp4"))
        let extractor = WebMediaExtractor(session: .shared)

        let items = try await extractor.extractMedia(from: url)

        #expect(items.count == 1)
        #expect(items[0].url == url)
        #expect(items[0].kind == .video)
        #expect(items[0].source == .web)
        #expect(items[0].title == "big")
    }

    @Test func hlsPlaylistReturnsVideoItem() async throws {
        let url = try #require(URL(string: "https://example.com/live/stream.m3u8"))
        let extractor = WebMediaExtractor(session: .shared)

        let items = try await extractor.extractMedia(from: url)

        #expect(items.count == 1)
        #expect(items[0].url == url)
        #expect(items[0].kind == .video)
    }

    @Test func directAudioReturnsAudioItem() async throws {
        let url = try #require(URL(string: "https://example.com/audio/song.mp3"))
        let extractor = WebMediaExtractor(session: .shared)

        let items = try await extractor.extractMedia(from: url)

        #expect(items.count == 1)
        #expect(items[0].kind == .audio)
    }

    @Test func unsupportedSchemeThrows() async throws {
        let url = try #require(URL(string: "ftp://example.com/movies/big.mp4"))
        let extractor = WebMediaExtractor(session: .shared)

        await #expect(throws: MediaExtractionError.self) {
            try await extractor.extractMedia(from: url)
        }
    }

    // MARK: - HTML5 video

    @Test func htmlVideoTagExtractsSourceAndPageTitle() async throws {
        let extractor = makeExtractor { _ in
            (
                statusCode: 200,
                data: Data(
                    """
                    <html><head><title>Test Page</title></head>
                    <body><video src="/media/movie.mp4" poster="/poster.jpg"></video></body>
                    </html>
                    """.utf8
                )
            )
        }
        let page = try #require(URL(string: "https://example.com/watch"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 1)
        #expect(items[0].url.absoluteString == "https://example.com/media/movie.mp4")
        #expect(items[0].title == "Test Page")
        #expect(items[0].kind == .video)
        #expect(items[0].source == .web)
    }

    @Test func posterUsedAsTitleFallbackWhenNoPageTitle() async throws {
        let extractor = makeExtractor { _ in
            (statusCode: 200, data: Data("<video src=\"/clip.mp4\" poster=\"/cover.jpg\"></video>".utf8))
        }
        let page = try #require(URL(string: "https://example.com/watch"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 1)
        #expect(items[0].title == "cover")
    }

    @Test func resolvesRelativeSourcesAndDeduplicates() async throws {
        let extractor = makeExtractor { _ in
            (
                statusCode: 200,
                data: Data(
                    """
                    <html><head><title>Series</title></head><body>
                    <video>
                      <source src="ep1.mp4">
                      <source src="/shows/ep1.mp4">
                      <source src="../clips/ep2.m3u8">
                    </video>
                    </body></html>
                    """.utf8
                )
            )
        }
        let page = try #require(URL(string: "https://example.com/shows/page"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 2)
        #expect(items.contains { $0.url.absoluteString == "https://example.com/shows/ep1.mp4" })
        #expect(items.contains { $0.url.absoluteString == "https://example.com/clips/ep2.m3u8" })
        #expect(items.allSatisfy { $0.source == .web })
    }

    @Test func singleQuotedAttributesAreParsed() async throws {
        let extractor = makeExtractor { _ in
            (statusCode: 200, data: Data("<video src='/clip.mp4'></video>".utf8))
        }
        let page = try #require(URL(string: "https://example.com/watch"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 1)
        #expect(items[0].url.absoluteString == "https://example.com/clip.mp4")
    }

    @Test func dataSrcAttributeIsExtracted() async throws {
        let extractor = makeExtractor { _ in
            (statusCode: 200, data: Data("<video data-src=\"/lazy.mp4\"></video>".utf8))
        }
        let page = try #require(URL(string: "https://example.com/watch"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 1)
        #expect(items[0].url.absoluteString == "https://example.com/lazy.mp4")
    }

    @Test func decodesHTMLEntitiesInTitleAndSource() async throws {
        let extractor = makeExtractor { _ in
            (
                statusCode: 200,
                data: Data(
                    """
                    <html><head><title>Tom &amp; Jerry &quot;Show&quot;</title></head>
                    <body><video src="/v?a=1&amp;b=2"></video></body></html>
                    """.utf8
                )
            )
        }
        let page = try #require(URL(string: "https://example.com/index"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 1)
        #expect(items[0].title == "Tom & Jerry \"Show\"")
        #expect(items[0].url.absoluteString == "https://example.com/v?a=1&b=2")
    }

    @Test func pageWithoutVideoReturnsEmpty() async throws {
        let extractor = makeExtractor { _ in
            (statusCode: 200, data: Data("<html><body><p>No video here</p></body></html>".utf8))
        }
        let page = try #require(URL(string: "https://example.com/text"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.isEmpty)
    }

    // MARK: - DRM 与协议边界

    @Test func drmMarkedVideoIsSkipped() async throws {
        let extractor = makeExtractor { _ in
            (
                statusCode: 200,
                data: Data(
                    """
                    <video encrypted><source src="https://example.com/movie.mp4"></video>
                    <video src="https://example.com/plain.mp4"></video>
                    """.utf8
                )
            )
        }
        let page = try #require(URL(string: "https://example.com/watch"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.count == 1)
        #expect(items[0].url.absoluteString == "https://example.com/plain.mp4")
    }

    @Test func nonHTTPSourcesAreSkipped() async throws {
        let extractor = makeExtractor { _ in
            (
                statusCode: 200,
                data: Data(
                    """
                    <video src="urn:uuid:deadbeef"></video>
                    <video><source src="data:video/mp4;base64,AAAA"></video>
                    """.utf8
                )
            )
        }
        let page = try #require(URL(string: "https://example.com/watch"))

        let items = try await extractor.extractMedia(from: page)

        #expect(items.isEmpty)
    }

    // MARK: - 错误与取消

    @Test func httpErrorThrows() async throws {
        let extractor = makeExtractor { _ in (statusCode: 404, data: Data()) }
        let page = try #require(URL(string: "https://example.com/missing"))

        await #expect(throws: MediaExtractionError.self) {
            try await extractor.extractMedia(from: page)
        }
    }

    @Test func extractionSupportsCancellation() async throws {
        let extractor = WebMediaExtractor(session: .shared)
        let url = try #require(URL(string: "https://example.com/movie.mp4"))
        let task = Task { try await extractor.extractMedia(from: url) }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    // MARK: - 测试辅助

    private func makeExtractor(
        handler: @escaping (URLRequest) throws -> (statusCode: Int, data: Data)
    ) -> WebMediaExtractor {
        MockURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let (statusCode, data) = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            ) else {
                throw URLError(.badServerResponse)
            }
            return (response, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return WebMediaExtractor(session: URLSession(configuration: configuration))
    }
}

/// 拦截 URLSession 请求并返回测试夹具的响应。
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

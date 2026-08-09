import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct LocalModelDownloadManagerTests {

    @Test func downloadsAllFilesAndCompletes() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptor = makeDescriptor()

        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "5"]
            )!
            return (http, Data("hello".utf8))
        }
        let manager = makeManager(descriptor: descriptor, directory: directory)

        manager.start()
        await waitUntil { manager.phase == .completed }

        #expect(manager.isModelDownloaded)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("a.bin").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("b.json").path
        ))
    }

    @Test func failureThenRetrySucceeds() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptor = makeDescriptor()

        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (http, Data())
        }
        let manager = makeManager(descriptor: descriptor, directory: directory)

        manager.start()
        await waitUntil { manager.phase == .failed }

        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "5"]
            )!
            return (http, Data("hello".utf8))
        }
        manager.start()
        await waitUntil { manager.phase == .completed }
        #expect(manager.isModelDownloaded)
    }

    @Test func cancelStopsDownload() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StallingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let manager = LocalModelDownloadManager(
            descriptor: makeDescriptor(),
            session: session,
            directoryProvider: { _ in directory }
        )

        manager.start()
        try? await Task.sleep(for: .milliseconds(200))
        manager.cancel()

        await waitUntil { manager.phase == .cancelled }
    }

    @Test func deleteRemovesFiles() async throws {
        let directory = makeTempDirectory()
        let descriptor = makeDescriptor()
        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "5"]
            )!
            return (http, Data("hello".utf8))
        }
        let manager = makeManager(descriptor: descriptor, directory: directory)

        manager.start()
        await waitUntil { manager.phase == .completed }
        #expect(FileManager.default.fileExists(atPath: directory.path))

        try await manager.deleteModel()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!manager.isModelDownloaded)
    }

    // MARK: - 辅助

    private func makeDescriptor() -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: "org/test-model",
            displayName: "Test Model",
            sizeLabel: "1 MB",
            requiredFiles: ["a.bin", "b.json"],
            extraEOSTokens: []
        )
    }

    private func makeManager(
        descriptor: LocalModelDescriptor,
        directory: URL
    ) -> LocalModelDownloadManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return LocalModelDownloadManager(
            descriptor: descriptor,
            session: session,
            directoryProvider: { _ in directory }
        )
    }

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("local-model-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - 测试替身

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            guard let (response, data) = try handler(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StallingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // 不回调：模拟慢速 / 卡住的下载，供取消测试使用。
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 30)
        }
    }

    override func stopLoading() {}
}

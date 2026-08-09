import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct CloudLLMTranslatorTests {

    @Test func translateSendsChatCompletionAndReturnsContent() async throws {
        let suite = uniqueSuiteName()
        let settings = makeSettings(
            suite: suite,
            baseURL: "https://api.example.com/v1",
            model: "test-model"
        )
        let store = InMemoryAPIKeyStore()
        try store.saveAPIKey("sk-test")

        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let body = #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#
            return (http, Data(body.utf8))
        }
        let translator = makeTranslator(settings: settings, apiKeyStore: store)

        let result = try await translator.translate(
            "Hello", from: "en", to: "zh-Hans", context: nil
        )

        #expect(result == "你好")
        #expect(StubURLProtocol.lastRequest?.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(StubURLProtocol.lastBody?.contains("Hello") == true)

        clearSuite(suite)
    }

    @Test func contextIsIncludedWhenProvided() async throws {
        let suite = uniqueSuiteName()
        let settings = makeSettings(
            suite: suite,
            baseURL: "https://api.example.com/v1",
            model: "test-model"
        )
        let store = InMemoryAPIKeyStore()
        try store.saveAPIKey("sk-test")

        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (http, Data(#"{"choices":[{"message":{"content":"译文"}}]}"#.utf8))
        }
        let translator = makeTranslator(settings: settings, apiKeyStore: store)

        _ = try await translator.translate(
            "Hello",
            from: "en",
            to: "zh-Hans",
            context: TranslationContext(text: "之前的剧情上下文")
        )

        #expect(StubURLProtocol.lastBody?.contains("之前的剧情上下文") == true)
        clearSuite(suite)
    }

    @Test func testConnectionSucceeds() async throws {
        let suite = uniqueSuiteName()
        let settings = makeSettings(
            suite: suite,
            baseURL: "https://api.example.com/v1",
            model: "test-model"
        )
        let store = InMemoryAPIKeyStore()
        try store.saveAPIKey("sk-test")
        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (http, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
        }
        let translator = makeTranslator(settings: settings, apiKeyStore: store)

        try await translator.testConnection()
        #expect(StubURLProtocol.lastRequest != nil)
        clearSuite(suite)
    }

    @Test func httpErrorSurfacesReadableMessage() async throws {
        let suite = uniqueSuiteName()
        let settings = makeSettings(
            suite: suite,
            baseURL: "https://api.example.com/v1",
            model: "test-model"
        )
        let store = InMemoryAPIKeyStore()
        try store.saveAPIKey("sk-test")
        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (http, Data(#"{"error":{"message":"Invalid API key"}}"#.utf8))
        }
        let translator = makeTranslator(settings: settings, apiKeyStore: store)

        do {
            try await translator.testConnection()
            Issue.record("expected http error")
        } catch let error as CloudLLMError {
            guard case .httpError(let statusCode, let message) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(statusCode == 401)
            #expect(message.contains("Invalid API key"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        clearSuite(suite)
    }

    @Test func emptyContentThrows() async throws {
        let suite = uniqueSuiteName()
        let settings = makeSettings(
            suite: suite,
            baseURL: "https://api.example.com/v1",
            model: "test-model"
        )
        let store = InMemoryAPIKeyStore()
        try store.saveAPIKey("sk-test")
        StubURLProtocol.handler = { request in
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (http, Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8))
        }
        let translator = makeTranslator(settings: settings, apiKeyStore: store)

        do {
            _ = try await translator.translate("Hello", from: "en", to: "zh-Hans", context: nil)
            Issue.record("expected empty content error")
        } catch let error as CloudLLMError {
            guard case .emptyContent = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        clearSuite(suite)
    }

    // MARK: - 辅助

    private func makeSettings(suite: String, baseURL: String, model: String) -> TranslationSettings {
        let settings = TranslationSettings(suiteName: suite)
        settings.cloudBaseURL = baseURL
        settings.cloudModelName = model
        return settings
    }

    private func makeTranslator(
        settings: TranslationSettings,
        apiKeyStore: any APIKeyStoring
    ) -> CloudLLMTranslator {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return CloudLLMTranslator(
            settings: settings,
            apiKeyStore: apiKeyStore,
            session: session
        )
    }

    private func uniqueSuiteName() -> String {
        "cloud-llm.\(UUID().uuidString)"
    }

    private func clearSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

// MARK: - 测试替身

private final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private var key: String?

    func saveAPIKey(_ key: String) throws {
        self.key = key
    }

    func loadAPIKey() throws -> String? {
        key
    }

    func deleteAPIKey() throws {
        key = nil
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? = nil
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            Self.lastRequest = request
            Self.lastBody = Self.readBody(of: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private static func readBody(of request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        // URLSession 可能把 httpBody 转为 httpBodyStream 再交给 URLProtocol。
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }

    override func stopLoading() {}
}

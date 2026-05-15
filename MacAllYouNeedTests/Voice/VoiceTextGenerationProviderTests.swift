import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceTextGenerationProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testAnthropicGenerateSendsExplicitSystemAndUserPrompt() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.url?.path, "/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(body["model"] as? String, "claude-test")
            XCTAssertEqual(body["system"] as? String, "You are a style summarizer.")
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.first?["role"] as? String, "user")
            XCTAssertEqual(messages.first?["content"] as? String, "pair list")
            return Self.response(body: #"{"content":[{"type":"text","text":"casual, no fillers"}]}"#)
        }
        let provider = AnthropicVoiceProvider(apiKey: "test-key", model: "claude-test", session: session)

        let result = try await provider.generate(systemPrompt: "You are a style summarizer.", userText: "pair list")

        XCTAssertEqual(result, "casual, no fillers")
    }

    func testOpenAICompatibleGenerateSendsExplicitSystemAndUserPrompt() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer oai-key")
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(body["model"] as? String, "gpt-test")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.first, ["role": "system", "content": "Summarize style."])
            XCTAssertEqual(messages.last, ["role": "user", "content": "user pairs"])
            return Self.response(body: #"{"choices":[{"message":{"content":"formal tone"}}]}"#)
        }
        let provider = OpenAICompatibleVoiceProvider(
            apiKey: "oai-key",
            model: "gpt-test",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            session: session
        )

        let result = try await provider.generate(systemPrompt: "Summarize style.", userText: "user pairs")

        XCTAssertEqual(result, "formal tone")
    }

    func testAnthropicGenerateDoesNotCallVoicePromptBuilder() async throws {
        let session = Self.mockSession { request in
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            let system = try XCTUnwrap(body["system"] as? String)
            XCTAssertFalse(system.contains("clean up dictated text"), "generate() must not inject the cleanup system prompt")
            return Self.response(body: #"{"content":[{"type":"text","text":"ok"}]}"#)
        }
        let provider = AnthropicVoiceProvider(apiKey: "k", model: "m", session: session)
        _ = try await provider.generate(systemPrompt: "Custom system.", userText: "user input")
    }

    func testAnthropicGenerateThrowsOnHttpError() async throws {
        let session = Self.mockSession { _ in Self.response(body: "{}", statusCode: 429) }
        let provider = AnthropicVoiceProvider(apiKey: "k", model: "m", session: session)

        do {
            _ = try await provider.generate(systemPrompt: "s", userText: "u")
            XCTFail("Expected throw")
        } catch VoiceLLMProviderError.httpStatus(let code) {
            XCTAssertEqual(code, 429)
        }
    }

    func testOpenAICompatibleGenerateThrowsOnInvalidResponse() async throws {
        let session = Self.mockSession { _ in Self.response(body: #"{"no_choices":[]}"#) }
        let provider = OpenAICompatibleVoiceProvider(
            apiKey: "k",
            model: "m",
            baseURL: URL(string: "https://api.example.com/v1")!,
            session: session
        )

        do {
            _ = try await provider.generate(systemPrompt: "s", userText: "u")
            XCTFail("Expected throw")
        } catch VoiceLLMProviderError.invalidResponse {
            // expected
        }
    }

    // MARK: - Helpers

    private static func mockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(body: String, statusCode: Int = 200) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://llm.example")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private static func jsonBody(from request: URLRequest) -> [String: Any]? {
        let data: Data?
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            data = Data(readingStream: stream)
        } else {
            data = nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private extension Data {
    init(readingStream stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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

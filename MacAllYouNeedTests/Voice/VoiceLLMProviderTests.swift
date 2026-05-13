import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceLLMProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testAnthropicProviderSendsMessagesRequestAndParsesText() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.url?.path, "/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(body["model"] as? String, "claude-test")
            XCTAssertTrue((body["system"] as? String)?.contains("zh+en mixed") == true)
            return Self.response(body: #"{"content":[{"type":"text","text":"cleaned text"}]}"#)
        }
        let provider = AnthropicVoiceProvider(apiKey: "test-key", model: "claude-test", session: session)

        let text = try await provider.clean(.fixture(text: "raw text", language: .mixed))

        XCTAssertEqual(text, "cleaned text")
    }

    func testOpenAICompatibleProviderSendsChatRequestAndParsesText() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(body["model"] as? String, "gpt-test")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.first?["role"], "system")
            XCTAssertEqual(messages.last?["role"], "user")
            return Self.response(body: #"{"choices":[{"message":{"content":"openai cleaned"}}]}"#)
        }
        let provider = try OpenAICompatibleVoiceProvider(
            apiKey: "test-key",
            model: "gpt-test",
            baseURL: XCTUnwrap(URL(string: "https://llm.example/v1")),
            session: session
        )

        let text = try await provider.clean(.fixture(text: "raw text", language: .english))

        XCTAssertEqual(text, "openai cleaned")
    }

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
        let data: Data? = if let httpBody = request.httpBody {
            httpBody
        } else if let stream = request.httpBodyStream {
            Data(reading: stream)
        } else {
            nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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

private extension VoiceLLMRequest {
    static func fixture(text: String, language: VoiceLanguage) -> VoiceLLMRequest {
        VoiceLLMRequest(
            text: text,
            rawText: text,
            appBundleID: "com.apple.TextEdit",
            language: language
        )
    }
}

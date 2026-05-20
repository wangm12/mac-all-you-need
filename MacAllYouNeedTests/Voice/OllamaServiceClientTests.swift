import Foundation
@testable import MacAllYouNeed
import XCTest

final class OllamaServiceClientTests: XCTestCase {
    override func tearDown() {
        OllamaMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testNativeBaseURLStripsTrailingOpenAIPath() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://localhost:11434/v1"))

        let root = OllamaServiceClient.nativeBaseURL(from: baseURL)

        XCTAssertEqual(root.absoluteString, "http://localhost:11434")
    }

    func testNativeBaseURLStripsTrailingOpenAIPathWithSlash() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://localhost:11434/v1/"))

        let root = OllamaServiceClient.nativeBaseURL(from: baseURL)

        XCTAssertEqual(root.absoluteString, "http://localhost:11434")
    }

    func testListModelsRequestsNativeTagsAndParsesNames() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/tags")
            return Self.response(body: #"{"models":[{"name":"qwen2.5:3b-instruct"},{"name":"gemma2:2b"}]}"#)
        }
        let client = OllamaServiceClient(
            baseURL: try XCTUnwrap(URL(string: "http://localhost:11434/v1")),
            session: session
        )

        let models = try await client.listModels()

        XCTAssertEqual(models.map(\.name), ["qwen2.5:3b-instruct", "gemma2:2b"])
    }

    func testPullModelPostsNameWithStreamingDisabled() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/pull")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(body["name"] as? String, "qwen2.5:3b-instruct")
            XCTAssertEqual(body["stream"] as? Bool, false)
            return Self.response(body: #"{"status":"success"}"#)
        }
        let client = OllamaServiceClient(
            baseURL: try XCTUnwrap(URL(string: "http://localhost:11434/v1")),
            session: session
        )

        try await client.pull(model: "qwen2.5:3b-instruct")
    }

    func testDeleteModelSendsNameInDeleteBody() async throws {
        let session = Self.mockSession { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/delete")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertEqual(body["name"] as? String, "qwen2.5:3b-instruct")
            return Self.response(body: #"{"status":"success"}"#)
        }
        let client = OllamaServiceClient(
            baseURL: try XCTUnwrap(URL(string: "http://localhost:11434/v1")),
            session: session
        )

        try await client.delete(model: "qwen2.5:3b-instruct")
    }

    func testOllamaDefaultModelUsesLowLatencyPreset() {
        XCTAssertEqual(VoiceCleanupProviderKind.ollama.defaultModel, "qwen2.5:3b-instruct")
    }

    private static func mockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        OllamaMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(body: String, statusCode: Int = 200) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "http://localhost:11434")!,
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

private final class OllamaMockURLProtocol: URLProtocol {
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

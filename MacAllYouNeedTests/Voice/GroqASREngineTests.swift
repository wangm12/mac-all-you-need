@testable import MacAllYouNeed
import XCTest

final class GroqASREngineTests: XCTestCase {
    override func tearDown() {
        GroqMockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - WAV encoding

    func testWAVHasCorrectRIFFHeader() {
        let samples: [Float] = [0.5, -0.5, 0.25]
        let wav = GroqASREngine.encodeWAV(samples: samples, sampleRate: 16000)

        XCTAssertGreaterThan(wav.count, 44)
        // RIFF
        XCTAssertEqual(wav[0 ... 3], Data("RIFF".utf8))
        // WAVE
        XCTAssertEqual(wav[8 ... 11], Data("WAVE".utf8))
        // fmt
        XCTAssertEqual(wav[12 ... 15], Data("fmt ".utf8))
        // data
        XCTAssertEqual(wav[36 ... 39], Data("data".utf8))
    }

    func testWAVSampleRateIsEmbedded() {
        let wav = GroqASREngine.encodeWAV(samples: [0.0], sampleRate: 16000)
        // bytes 24..27 = sample rate as little-endian UInt32
        let sr = UInt32(wav[24]) | UInt32(wav[25]) << 8 | UInt32(wav[26]) << 16 | UInt32(wav[27]) << 24
        XCTAssertEqual(sr, 16000)
    }

    func testWAVSamplesClampedToInt16Range() {
        let samples: [Float] = [2.0, -2.0, 0.5]
        let wav = GroqASREngine.encodeWAV(samples: samples, sampleRate: 16000)
        let dataOffset = 44
        let s0 = Int16(bitPattern: UInt16(wav[dataOffset]) | UInt16(wav[dataOffset + 1]) << 8)
        let s1 = Int16(bitPattern: UInt16(wav[dataOffset + 2]) | UInt16(wav[dataOffset + 3]) << 8)
        XCTAssertEqual(s0, Int16.max)
        XCTAssertEqual(s1, Int16.min)
    }

    func testWAVFileSize() {
        let n = 100
        let samples = [Float](repeating: 0.0, count: n)
        let wav = GroqASREngine.encodeWAV(samples: samples, sampleRate: 16000)
        XCTAssertEqual(wav.count, 44 + n * 2)
    }

    // MARK: - HTTP request shape

    func testGroqRequestSendsAuthAndModel() async throws {
        let session = mockSession { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-groq-key")
            let ct = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary="), "Content-Type must be multipart")
            XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
            return self.jsonResponse(body: #"{"text":"hello world"}"#)
        }
        let engine = makeEngine(apiKey: "test-groq-key", session: session)
        let result = try await engine.transcribe(
            samples: [Float](repeating: 0, count: 16000),
            sampleRate: 16000,
            options: .init(preferredModelIdentifier: nil)
        )
        XCTAssertEqual(result.text, "hello world")
    }

    func testGroqRequestBodyContainsModelField() async throws {
        let session = mockSession { request in
            let body = self.bodyData(from: request)
            XCTAssertNotNil(body.range(of: Data("whisper-large-v3-turbo".utf8)), "body must include model id")
            return self.jsonResponse(body: #"{"text":"ok"}"#)
        }
        let engine = makeEngine(apiKey: "k", session: session, modelID: .whisperLargeV3Turbo)
        _ = try await engine.transcribe(
            samples: [Float](repeating: 0, count: 8000),
            sampleRate: 16000,
            options: .init(preferredModelIdentifier: nil)
        )
    }

    func testGroqRequestIncludesLanguageWhenSet() async throws {
        let session = mockSession { request in
            let body = self.bodyData(from: request)
            XCTAssertNotNil(body.range(of: Data("zh".utf8)), "body must contain language code 'zh'")
            return self.jsonResponse(body: #"{"text":"你好"}"#)
        }
        let engine = makeEngine(apiKey: "k", session: session, languageHint: .chinese)
        _ = try await engine.transcribe(
            samples: [Float](repeating: 0, count: 8000),
            sampleRate: 16000,
            options: .init(preferredModelIdentifier: nil)
        )
    }

    func testGroqThrowsOnHTTP401() async {
        let session = mockSession { _ in self.jsonResponse(body: "{}", statusCode: 401) }
        let engine = makeEngine(apiKey: "bad-key", session: session)
        do {
            _ = try await engine.transcribe(
                samples: [Float](repeating: 0, count: 8000),
                sampleRate: 16000,
                options: .init(preferredModelIdentifier: nil)
            )
            XCTFail("Expected throw")
        } catch let GroqASRError.httpError(code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGroqThrowsMissingAPIKeyWhenNoKey() async {
        let session = mockSession { _ in self.jsonResponse(body: #"{"text":""}"#) }
        let engine = makeEngine(apiKey: "", session: session)
        do {
            _ = try await engine.transcribe(
                samples: [Float](repeating: 0, count: 8000),
                sampleRate: 16000,
                options: .init(preferredModelIdentifier: nil)
            )
            XCTFail("Expected throw")
        } catch GroqASRError.missingAPIKey {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenAITranscribeRequestShape() async throws {
        let session = mockSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-openai-key")
            let body = self.bodyData(from: request)
            XCTAssertNotNil(body.range(of: Data("gpt-4o-transcribe".utf8)))
            XCTAssertNotNil(body.range(of: Data("en".utf8)))
            return self.jsonResponse(body: #"{"text":"openai text"}"#)
        }
        let engine = makeCloudEngine(
            providerKind: .openAITranscribe,
            modelID: .openAIGPT4oTranscribe,
            languageHint: .english,
            apiKey: "test-openai-key",
            session: session
        )

        let result = try await engine.transcribe(
            samples: [Float](repeating: 0, count: 8000),
            sampleRate: 16000,
            options: .init(preferredModelIdentifier: nil)
        )

        XCTAssertEqual(result.text, "openai text")
        XCTAssertEqual(result.modelIdentifier, VoiceCloudASRModelID.openAIGPT4oTranscribe.rawValue)
    }

    func testElevenLabsScribeRequestShape() async throws {
        let session = mockSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-eleven-key")
            let body = self.bodyData(from: request)
            XCTAssertNotNil(body.range(of: Data("scribe_v2".utf8)))
            XCTAssertNotNil(body.range(of: Data("model_id".utf8)))
            return self.jsonResponse(body: #"{"text":"scribe text"}"#)
        }
        let engine = makeCloudEngine(
            providerKind: .elevenLabs,
            modelID: .elevenLabsScribeV2,
            apiKey: "test-eleven-key",
            session: session
        )

        let result = try await engine.transcribe(
            samples: [Float](repeating: 0, count: 8000),
            sampleRate: 16000,
            options: .init(preferredModelIdentifier: nil)
        )

        XCTAssertEqual(result.text, "scribe text")
    }

    func testDeepgramNovaRequestShape() async throws {
        let session = mockSession { request in
            XCTAssertEqual(request.url?.path, "/v1/listen")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token test-deepgram-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["model"], "nova-3")
            XCTAssertEqual(query["smart_format"], "true")
            XCTAssertEqual(query["language"], "zh")
            return self.jsonResponse(
                body: #"{"results":{"channels":[{"alternatives":[{"transcript":"deepgram text"}]}]}}"#
            )
        }
        let engine = makeCloudEngine(
            providerKind: .deepgram,
            modelID: .deepgramNova3,
            languageHint: .chinese,
            apiKey: "test-deepgram-key",
            session: session
        )

        let result = try await engine.transcribe(
            samples: [Float](repeating: 0, count: 8000),
            sampleRate: 16000,
            options: .init(preferredModelIdentifier: nil)
        )

        XCTAssertEqual(result.text, "deepgram text")
    }

    // MARK: - VoiceASRSettings persistence

    func testVoiceASRSettingsPreservesGroqProviderKind() throws {
        let original = VoiceASRSettings(modelID: .qwen3ASR06BF32, languageHint: .automatic, providerKind: .groq)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceASRSettings.self, from: data)
        XCTAssertEqual(decoded.providerKind, .groq)
    }

    func testVoiceASRSettingsDefaultsToLocalWhenProviderKindMissing() throws {
        let json = #"{"modelID":"qwen3-asr-0.6b-f32","languageHint":"automatic"}"#
        let decoded = try JSONDecoder().decode(VoiceASRSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.providerKind, .local)
    }

    // MARK: - Helpers

    private func makeEngine(
        apiKey: String,
        session: URLSession,
        modelID: GroqASRModelID = .whisperLargeV3Turbo,
        languageHint: VoiceASRLanguageHint = .automatic
    ) -> GroqASREngine {
        GroqASREngine(
            settings: { GroqASRSettings(modelID: modelID, languageHint: languageHint) },
            apiKeyProvider: { apiKey.isEmpty ? nil : apiKey },
            session: session
        )
    }

    private func makeCloudEngine(
        providerKind: VoiceASRProviderKind,
        modelID: VoiceCloudASRModelID,
        languageHint: VoiceASRLanguageHint = .automatic,
        apiKey: String,
        session: URLSession
    ) -> VoiceCloudASREngine {
        VoiceCloudASREngine(
            providerKind: providerKind,
            settings: { VoiceCloudASRSettings(modelID: modelID, languageHint: languageHint) },
            apiKeyProvider: { requestedProvider in
                requestedProvider == providerKind && !apiKey.isEmpty ? apiKey : nil
            },
            session: session
        )
    }

    private func bodyData(from request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        var result = Data()
        stream.open()
        defer { stream.close() }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: 4096)
            guard n > 0 else { break }
            result.append(buf, count: n)
        }
        return result
    }

    private func mockSession(handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)) -> URLSession {
        GroqMockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroqMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func jsonResponse(body: String, statusCode: Int = 200) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://api.groq.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

// MARK: - Test doubles

private final class GroqMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
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
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

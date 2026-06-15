import Core
import Foundation
import OSLog

private let log = Logger(subsystem: "com.macallyouneed.voice", category: "groq-asr")

/// VoiceTranscriptionEngine implementation that sends audio to Groq's Whisper API.
///
/// Audio is encoded in-memory as a standard RIFF WAV file (16kHz, 16-bit, mono)
/// and uploaded via multipart/form-data. The response is plain JSON with a `text` field.
///
/// Privacy: audio is sent to Groq's servers. User must provide their own API key (BYOK).
actor GroqASREngine: VoiceTranscriptionEngine {
    private let settings: () -> GroqASRSettings
    private let apiKeyProvider: () throws -> String?
    private let session: URLSession

    nonisolated var modelIdentifier: String {
        "groq-\(GroqASRSettingsStore.load().modelID.rawValue)"
    }

    nonisolated var capabilities: VoiceASRCapabilities {
        .init(supportsStreaming: false, requiresNetwork: true, emitsPartials: false)
    }

    /// Production init — reads from Keychain.
    init(settings: @escaping () -> GroqASRSettings, keyStore: GroqASRKeyStore, session: URLSession = .shared) {
        self.init(settings: settings, apiKeyProvider: { try keyStore.apiKey() }, session: session)
    }

    /// Testable init — inject the API key directly.
    init(
        settings: @escaping () -> GroqASRSettings,
        apiKeyProvider: @escaping () throws -> String?,
        session: URLSession = .shared
    ) {
        self.settings = settings
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options _: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        let currentSettings = settings()
        let capturedModelID = "groq-\(currentSettings.modelID.rawValue)"

        guard let apiKey = try apiKeyProvider() else {
            throw GroqASRError.missingAPIKey
        }

        let resampled = AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        let wavData = Self.encodeWAV(samples: resampled, sampleRate: 16000)

        log.info("Groq ASR: \(resampled.count / 16000, privacy: .public)s audio → \(currentSettings.modelID.rawValue, privacy: .public)")

        // Free tier limit: 25 MB. Use 24 MB as safe ceiling to leave room for
        // multipart overhead. A 13-minute WAV at 16kHz 16-bit is ~24.96 MB.
        let maxBytes = 24 * 1024 * 1024
        guard wavData.count <= maxBytes else {
            throw GroqASRError.fileTooLarge(seconds: resampled.count / 16000)
        }

        let text = try await uploadToGroq(
            wavData: wavData,
            apiKey: apiKey,
            modelID: currentSettings.modelID.rawValue,
            language: currentSettings.groqLanguageCode
        )

        return VoiceTranscriptionResult(
            text: text,
            language: .mixed,
            modelIdentifier: capturedModelID
        )
    }

    // MARK: - HTTP

    private func uploadToGroq(
        wavData: Data,
        apiKey: String,
        modelID: String,
        language: String?
    ) async throws -> String {
        let boundary = "GroqASR-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(
            wavData: wavData,
            modelID: modelID,
            language: language,
            boundary: boundary
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GroqASRError.invalidResponse
        }
        guard 200 ..< 300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            log.error("Groq ASR HTTP \(http.statusCode, privacy: .public): \(body, privacy: .private)")
            throw GroqASRError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw GroqASRError.invalidResponse
        }

        log.info("Groq ASR: received \(text.count, privacy: .public) chars")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildMultipartBody(
        wavData: Data,
        modelID: String,
        language: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        // file field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n")

        // model field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append(modelID)
        append("\r\n")

        // response_format field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("json")
        append("\r\n")

        // language field (optional)
        if let lang = language {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append(lang)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - WAV encoding

    /// Encodes Float32 PCM samples as a standard 16-bit mono RIFF WAV file.
    static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        VoiceAudioCodec.encodeWAV(samples: samples, sampleRate: sampleRate)
    }
}

// MARK: - Errors

enum GroqASRError: LocalizedError {
    case missingAPIKey
    case httpError(Int)
    case invalidResponse
    case fileTooLarge(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Groq API key not configured. Add your key in Voice Settings → Recognition."
        case let .httpError(code):
            "Groq API returned HTTP \(code). Check your API key."
        case .invalidResponse:
            "Groq API returned an unexpected response."
        case let .fileTooLarge(seconds):
            "Recording (\(seconds)s) exceeds Groq's 25 MB upload limit (~13 min). Split into shorter segments."
        }
    }
}

// MARK: - Shared cloud ASR engine

private let cloudASRLog = Logger(subsystem: "com.macallyouneed.voice", category: "cloud-asr")

actor VoiceCloudASREngine: VoiceTranscriptionEngine {
    private let providerKind: VoiceASRProviderKind
    private let settings: () -> VoiceCloudASRSettings
    private let apiKeyProvider: (VoiceASRProviderKind) throws -> String?
    private let session: URLSession

    nonisolated var modelIdentifier: String {
        let settings = VoiceCloudASRSettingsStore.load()
        return settings.modelID.rawValue
    }

    nonisolated var capabilities: VoiceASRCapabilities {
        .init(supportsStreaming: false, requiresNetwork: true, emitsPartials: false)
    }

    init(
        providerKind: VoiceASRProviderKind,
        settings: @escaping () -> VoiceCloudASRSettings,
        keyStore: VoiceCloudASRKeyStore,
        session: URLSession = .shared
    ) {
        self.init(
            providerKind: providerKind,
            settings: settings,
            apiKeyProvider: { try keyStore.apiKey(for: $0) },
            session: session
        )
    }

    init(
        providerKind: VoiceASRProviderKind,
        settings: @escaping () -> VoiceCloudASRSettings,
        apiKeyProvider: @escaping (VoiceASRProviderKind) throws -> String?,
        session: URLSession = .shared
    ) {
        self.providerKind = providerKind
        self.settings = settings
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options _: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        let currentSettings = settings()
        let modelID = currentSettings.modelID(for: providerKind)
        guard let apiKey = try apiKeyProvider(modelID.providerKind) else {
            throw VoiceCloudASRError.missingAPIKey(modelID.providerKind)
        }

        let resampled = AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        let wavData = VoiceAudioCodec.encodeWAV(samples: resampled, sampleRate: 16000)
        let seconds = resampled.count / 16000
        let maxBytes = 24 * 1024 * 1024
        guard wavData.count <= maxBytes else {
            throw VoiceCloudASRError.fileTooLarge(provider: modelID.providerKind, seconds: seconds)
        }

        cloudASRLog.info("Cloud ASR upload start — provider: \(modelID.providerKind.rawValue, privacy: .public) model: \(modelID.providerModelID, privacy: .public) seconds: \(seconds, privacy: .public)")

        let text: String = switch modelID.providerKind {
        case .local:
            throw VoiceCloudASRError.unsupportedProvider(modelID.providerKind)
        case .groq:
            try await uploadOpenAICompatible(
                endpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
                authorizationHeader: "Bearer \(apiKey)",
                wavData: wavData,
                modelID: modelID.providerModelID,
                language: currentSettings.iso639LanguageCode,
                providerKind: modelID.providerKind
            )
        case .openAITranscribe:
            try await uploadOpenAICompatible(
                endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                authorizationHeader: "Bearer \(apiKey)",
                wavData: wavData,
                modelID: modelID.providerModelID,
                language: currentSettings.iso639LanguageCode,
                providerKind: modelID.providerKind
            )
        case .elevenLabs:
            try await uploadElevenLabs(
                wavData: wavData,
                apiKey: apiKey,
                modelID: modelID.providerModelID,
                language: currentSettings.iso639LanguageCode
            )
        case .deepgram:
            try await uploadDeepgram(
                wavData: wavData,
                apiKey: apiKey,
                modelID: modelID.providerModelID,
                language: currentSettings.iso639LanguageCode
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cloudASRLog.info("Cloud ASR received — provider: \(modelID.providerKind.rawValue, privacy: .public) chars: \(trimmed.count, privacy: .public)")
        return VoiceTranscriptionResult(
            text: trimmed,
            language: currentSettings.languageHint == .english ? .english : .mixed,
            modelIdentifier: modelID.rawValue
        )
    }

    private func uploadOpenAICompatible(
        endpoint: URL,
        authorizationHeader: String,
        wavData: Data,
        modelID: String,
        language: String?,
        providerKind: VoiceASRProviderKind
    ) async throws -> String {
        let boundary = "CloudASR-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            wavData: wavData,
            modelFieldName: "model",
            modelID: modelID,
            languageFieldName: "language",
            language: language,
            boundary: boundary,
            extraTextFields: ["response_format": "json"]
        )

        let data = try await data(for: request, providerKind: providerKind)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw VoiceCloudASRError.invalidResponse(providerKind)
        }
        return text
    }

    private func uploadElevenLabs(
        wavData: Data,
        apiKey: String,
        modelID: String,
        language: String?
    ) async throws -> String {
        let boundary = "ElevenLabsASR-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            wavData: wavData,
            modelFieldName: "model_id",
            modelID: modelID,
            languageFieldName: "language_code",
            language: language,
            boundary: boundary
        )

        let data = try await data(for: request, providerKind: .elevenLabs)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw VoiceCloudASRError.invalidResponse(.elevenLabs)
        }
        return text
    }

    private func uploadDeepgram(
        wavData: Data,
        apiKey: String,
        modelID: String,
        language: String?
    ) async throws -> String {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var queryItems = [
            URLQueryItem(name: "model", value: modelID),
            URLQueryItem(name: "smart_format", value: "true")
        ]
        if let language {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let data = try await data(for: request, providerKind: .deepgram)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String
        else {
            throw VoiceCloudASRError.invalidResponse(.deepgram)
        }
        return transcript
    }

    private func data(for request: URLRequest, providerKind: VoiceASRProviderKind) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceCloudASRError.invalidResponse(providerKind)
        }
        guard 200 ..< 300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            cloudASRLog.error("Cloud ASR HTTP \(http.statusCode, privacy: .public) provider: \(providerKind.rawValue, privacy: .public) body: \(body, privacy: .private)")
            throw VoiceCloudASRError.httpError(provider: providerKind, code: http.statusCode)
        }
        return data
    }

    private static func multipartBody(
        wavData: Data,
        modelFieldName: String,
        modelID: String,
        languageFieldName: String,
        language: String?,
        boundary: String,
        extraTextFields: [String: String] = [:]
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(modelFieldName)\"\r\n\r\n")
        append(modelID)
        append("\r\n")

        for (name, value) in extraTextFields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append(value)
            append("\r\n")
        }

        if let language {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(languageFieldName)\"\r\n\r\n")
            append(language)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")
        return body
    }
}

enum VoiceCloudASRError: LocalizedError {
    case missingAPIKey(VoiceASRProviderKind)
    case unsupportedProvider(VoiceASRProviderKind)
    case httpError(provider: VoiceASRProviderKind, code: Int)
    case invalidResponse(VoiceASRProviderKind)
    case fileTooLarge(provider: VoiceASRProviderKind, seconds: Int)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            "\(provider.apiKeyLabel) is not configured."
        case let .unsupportedProvider(provider):
            "\(provider.label) is not supported by the cloud ASR runtime."
        case let .httpError(provider, code):
            "\(provider.label) returned HTTP \(code). Check your API key and model access."
        case let .invalidResponse(provider):
            "\(provider.label) returned an unexpected response."
        case let .fileTooLarge(provider, seconds):
            "Recording (\(seconds)s) exceeds \(provider.label)'s upload safety limit. Split into shorter segments."
        }
    }
}

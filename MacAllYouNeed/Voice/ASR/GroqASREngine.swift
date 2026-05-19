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

    /// Production init — reads from Keychain.
    convenience init(settings: @escaping () -> GroqASRSettings, keyStore: GroqASRKeyStore, session: URLSession = .shared) {
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

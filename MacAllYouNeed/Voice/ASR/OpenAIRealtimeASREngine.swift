import Core
import Foundation
import OSLog

private let realtimeEngineLog = Logger(subsystem: "com.macallyouneed.voice", category: "openai-realtime-engine")

/// ASR engine that connects to the OpenAI Realtime transcription API over WebSocket.
/// Conforms to both VoiceTranscriptionEngine (batch fallback for retry/history) and
/// VoiceLiveTranscriptionEngine (true streaming with partial transcripts).
///
/// Selection: .openAIRealtime in VoiceASRProviderKind.
/// Key reuse: VoiceCloudASRKeyStore, account for .openAITranscribe.
final class OpenAIRealtimeASREngine: VoiceLiveTranscriptionEngine {

    // MARK: - Constants

    private static let webSocketURL = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-transcribe")!
    private static let apiVersion = "realtime=v1"

    // MARK: - Dependencies

    private let keyStore: VoiceCloudASRKeyStore
    private let settings: () -> VoiceCloudASRSettings
    private let batchFallback: VoiceCloudASREngine
    private let urlSession: URLSession

    // MARK: - ASRProviding / VoiceTranscriptionEngine

    var modelIdentifier: String { "openai-realtime-gpt-4o-transcribe" }

    var capabilities: VoiceASRCapabilities {
        VoiceASRCapabilities(supportsStreaming: true, requiresNetwork: true, emitsPartials: true)
    }

    // MARK: - Init

    init(
        keyStore: VoiceCloudASRKeyStore,
        settings: @escaping () -> VoiceCloudASRSettings,
        urlSession: URLSession = .shared
    ) {
        self.keyStore = keyStore
        self.settings = settings
        self.urlSession = urlSession
        // Batch fallback reuses the existing OpenAI-transcribe implementation.
        self.batchFallback = VoiceCloudASREngine(
            providerKind: .openAITranscribe,
            settings: settings,
            keyStore: keyStore
        )
    }

    // MARK: - Batch transcription (for retry-from-history and offline fallback)

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        try await batchFallback.transcribe(samples: samples, sampleRate: sampleRate, options: options)
    }

    // MARK: - Live streaming session

    func makeLiveSession(options _: VoiceTranscriptionOptions) async throws -> any VoiceLiveTranscriptionSession {
        guard let apiKey = try? keyStore.apiKey(for: .openAITranscribe), !apiKey.isEmpty else {
            throw OpenAIRealtimeError.missingAPIKey
        }

        var request = URLRequest(url: Self.webSocketURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "OpenAI-Beta")

        let task = urlSession.webSocketTask(with: request)
        let session = OpenAIRealtimeSession(webSocketTask: task)

        let currentSettings = settings()
        let languageHint = currentSettings.iso639LanguageCode
        try await session.configure(languageHint: languageHint)
        realtimeEngineLog.info("OpenAI Realtime live session started")
        return session
    }
}

import Core
import Foundation
import OSLog

private let realtimeLog = Logger(subsystem: "com.macallyouneed.voice", category: "openai-realtime")

/// WebSocket session for OpenAI Realtime transcription API.
/// Streams PCM16 audio and receives partial + final transcripts.
///
/// Protocol reference: https://platform.openai.com/docs/guides/realtime
/// Endpoint: wss://api.openai.com/v1/realtime?model=gpt-4o-transcribe
actor OpenAIRealtimeSession: VoiceLiveTranscriptionSession {

    private let webSocketTask: URLSessionWebSocketTask
    private var receiveTask: Task<Void, Never>?
    private var partialHandler: (@Sendable (VoiceTranscriptionPartial) -> Void)?
    private var accumulatedTranscript = ""
    private var finalTranscript: String?
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var isCancelled = false

    static let targetSampleRate: Double = 16000

    // MARK: - Init / connect

    init(webSocketTask: URLSessionWebSocketTask) {
        self.webSocketTask = webSocketTask
    }

    /// Send the session configuration and start the receive loop.
    func configure(languageHint: String?) async throws {
        webSocketTask.resume()

        // Configure transcription session.
        var sessionConfig: [String: Any] = [
            "input_audio_format": "pcm16",
            "modalities": ["text"],
        ]
        if let lang = languageHint {
            sessionConfig["language"] = lang
        }
        let configEvent: [String: Any] = [
            "type": "transcription_session.update",
            "session": sessionConfig,
        ]
        try await send(configEvent)

        // Start the receive loop.
        receiveTask = Task { await self.receiveLoop() }
        realtimeLog.info("OpenAI Realtime session configured")
    }

    // MARK: - VoiceLiveTranscriptionSession

    func setPartialHandler(_ handler: @escaping @Sendable (VoiceTranscriptionPartial) -> Void) async {
        partialHandler = handler
    }

    func enqueueAudio(samples: [Float], sampleRate: Double) async throws {
        guard !isCancelled else { return }
        let resampled = sampleRate == Self.targetSampleRate
            ? samples
            : AudioCaptureService.resample(samples, from: sampleRate, to: Self.targetSampleRate)
        guard !resampled.isEmpty else { return }
        let pcm16 = VoiceAudioCodec.pcm16Data(samples: resampled)
        let base64 = pcm16.base64EncodedString()
        let event: [String: Any] = ["type": "input_audio_buffer.append", "audio": base64]
        try await send(event)
    }

    func finish() async throws -> VoiceTranscriptionResult {
        try await finish(context: nil)
    }

    func finish(context _: VoiceLiveFinishContext?) async throws -> VoiceTranscriptionResult {
        guard !isCancelled else { throw VoiceLiveTranscriptionError.cancelled }

        // Commit the audio buffer and request transcription.
        try await send(["type": "input_audio_buffer.commit"])
        realtimeLog.info("OpenAI Realtime: audio committed, waiting for final transcript")

        // Wait for the final transcript (up to 5s).
        let text = try await withTimeout(seconds: 5) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                Task {
                    await self.setFinalContinuation(cont)
                    // If final already arrived before we set up the continuation, resolve immediately.
                    if let final = await self.finalTranscript {
                        await self.resolveFinalContinuation(with: .success(final))
                    }
                }
            }
        } ?? accumulatedTranscript

        webSocketTask.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()

        return VoiceTranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: .mixed,
            modelIdentifier: "openai-realtime"
        )
    }

    func cancel() async {
        isCancelled = true
        resolveFinalContinuation(with: .failure(VoiceLiveTranscriptionError.cancelled))
        webSocketTask.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
    }

    // MARK: - Private

    private func setFinalContinuation(_ cont: CheckedContinuation<String, Error>) {
        finalContinuation = cont
    }

    private func resolveFinalContinuation(with result: Result<String, Error>) {
        guard let cont = finalContinuation else { return }
        finalContinuation = nil
        cont.resume(with: result)
    }

    private func receiveLoop() async {
        while !isCancelled {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !isCancelled {
                    realtimeLog.error("OpenAI Realtime receive error: \(error.localizedDescription, privacy: .public)")
                    resolveFinalContinuation(with: .failure(error))
                }
                return
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            // Partial transcript delta.
            if let delta = json["delta"] as? [String: Any],
               let transcript = delta["transcript"] as? String, !transcript.isEmpty
            {
                accumulatedTranscript += transcript
                let current = accumulatedTranscript
                let handler = partialHandler
                handler?(.init(text: current, isStable: false))
            }

        case "conversation.item.input_audio_transcription.completed":
            // Final transcript for a committed buffer.
            let transcript: String
            if let t = json["transcript"] as? String {
                transcript = t
            } else if let item = json["item"] as? [String: Any],
                      let content = item["content"] as? [[String: Any]],
                      let first = content.first,
                      let t = first["transcript"] as? String {
                transcript = t
            } else {
                transcript = accumulatedTranscript
            }
            finalTranscript = transcript
            realtimeLog.info("OpenAI Realtime: final transcript received (\(transcript.count, privacy: .public) chars)")
            resolveFinalContinuation(with: .success(transcript))

        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            realtimeLog.error("OpenAI Realtime error: \(errorMsg, privacy: .public)")
            resolveFinalContinuation(with: .failure(OpenAIRealtimeError.serverError(errorMsg)))

        default:
            break
        }
    }

    private func send(_ event: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await webSocketTask.send(.string(text))
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T? {
        try await withThrowingTaskGroup(of: Optional<T>.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
}

enum OpenAIRealtimeError: Error {
    case serverError(String)
    case connectionFailed
    case missingAPIKey
}

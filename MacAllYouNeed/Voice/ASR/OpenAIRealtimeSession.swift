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
    private var isCancelled = false

    static let targetSampleRate: Double = 16000

    // MARK: - Init / connect

    init(webSocketTask: URLSessionWebSocketTask) {
        self.webSocketTask = webSocketTask
    }

    /// Send the session configuration and start the receive loop.
    /// Cancels and closes the socket if configuration messaging fails.
    func configure(languageHint: String?) async throws {
        webSocketTask.resume()
        do {
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
            receiveTask = Task { await self.receiveLoop() }
            realtimeLog.info("OpenAI Realtime session configured")
        } catch {
            // Close the socket so the underlying connection isn't leaked.
            webSocketTask.cancel(with: .goingAway, reason: nil)
            throw error
        }
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

        try await send(["type": "input_audio_buffer.commit"])
        realtimeLog.info("OpenAI Realtime: audio committed, waiting for final transcript")

        // Poll for the final transcript (set by receiveLoop on the actor) with a 5s deadline.
        // Polling avoids the actor-isolation issue of withCheckedThrowingContinuation bodies
        // being nonisolated; max latency after the event arrives is one 50ms sleep interval.
        let deadline = ContinuousClock.now + .seconds(5)
        while finalTranscript == nil, !isCancelled, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        let text = (finalTranscript ?? accumulatedTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        webSocketTask.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()

        return VoiceTranscriptionResult(
            text: text,
            language: .mixed,
            modelIdentifier: "openai-realtime"
        )
    }

    func cancel() async {
        isCancelled = true
        webSocketTask.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
    }

    // MARK: - Private

    private func receiveLoop() async {
        while !isCancelled {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !isCancelled {
                    realtimeLog.error("OpenAI Realtime receive error: \(error.localizedDescription, privacy: .public)")
                    // Mark cancelled so the polling loop in finish() exits at next iteration.
                    isCancelled = true
                }
                return
            }
        }
    }

    // Non-async: already on actor, no suspension needed.
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            // Delta is a plain String, not a nested dict.
            if let delta = json["delta"] as? String, !delta.isEmpty {
                accumulatedTranscript += delta
                let current = accumulatedTranscript
                partialHandler?(.init(text: current, isStable: false))
            }

        case "conversation.item.input_audio_transcription.completed":
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
            // finish() polls finalTranscript; setting it here is sufficient.

        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            realtimeLog.error("OpenAI Realtime error: \(errorMsg, privacy: .public)")
            // Mark as cancelled so the polling loop in finish() exits promptly.
            isCancelled = true

        default:
            break
        }
    }

    private func send(_ event: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await webSocketTask.send(.string(text))
    }
}

enum OpenAIRealtimeError: Error {
    case serverError(String)
    case connectionFailed
    case missingAPIKey
}

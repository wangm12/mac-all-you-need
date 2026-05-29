import Foundation

struct AnthropicVoiceProvider: VoiceLLMProvider, VoiceTextGenerationProvider {
    let providerIdentifier = "anthropic"

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    init(
        apiKey: String,
        model: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    func clean(_ request: VoiceLLMRequest) async throws -> String {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1024,
            "temperature": 0,
            "system": VoicePromptBuilder.systemPrompt(context: request.promptContext),
            "messages": [
                [
                    "role": "user",
                    "content": VoicePromptBuilder.userPrompt(transcript: request.text)
                ]
            ]
        ])

        let data = try await Self.data(for: urlRequest, session: session)
        return try Self.parseText(from: data)
    }

    func cleanStreaming(_ request: VoiceLLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 1024,
                        "temperature": 0,
                        "stream": true,
                        "system": VoicePromptBuilder.systemPrompt(context: request.promptContext),
                        "messages": [
                            [
                                "role": "user",
                                "content": VoicePromptBuilder.userPrompt(transcript: request.text)
                            ]
                        ]
                    ])

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw VoiceLLMProviderError.invalidResponse
                    }
                    guard 200 ..< 300 ~= httpResponse.statusCode else {
                        throw VoiceLLMProviderError.httpStatus(httpResponse.statusCode)
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]" else { continue }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = object["type"] as? String
                        else { continue }

                        if type == "error" {
                            continuation.finish(throwing: VoiceLLMProviderError.invalidResponse)
                            return
                        }
                        guard type == "content_block_delta",
                              let delta = object["delta"] as? [String: Any],
                              let deltaType = delta["type"] as? String,
                              deltaType == "text_delta",
                              let text = delta["text"] as? String,
                              !text.isEmpty
                        else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generate(systemPrompt: String, userText: String) async throws -> String {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 512,
            "temperature": 0,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userText]]
        ])
        let data = try await Self.data(for: urlRequest, session: session)
        return try Self.parseText(from: data)
    }

    private static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceLLMProviderError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw VoiceLLMProviderError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private static func parseText(from data: Data) throws -> String {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = object["content"] as? [[String: Any]],
            let text = content.compactMap({ $0["text"] as? String }).first
        else {
            throw VoiceLLMProviderError.invalidResponse
        }
        return text
    }
}

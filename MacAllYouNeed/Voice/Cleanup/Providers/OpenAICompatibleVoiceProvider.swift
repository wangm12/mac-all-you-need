import Foundation

struct OpenAICompatibleVoiceProvider: VoiceLLMProvider, VoiceTextGenerationProvider {
    let providerIdentifier = "openai-compatible"

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    init(apiKey: String, model: String, baseURL: URL, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    func clean(_ request: VoiceLLMRequest) async throws -> String {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "system",
                    "content": VoicePromptBuilder.systemPrompt(context: request.promptContext)
                ],
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
                    var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !apiKey.isEmpty {
                        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "temperature": 0,
                        "max_tokens": 1024,
                        "stream": true,
                        "messages": [
                            [
                                "role": "system",
                                "content": VoicePromptBuilder.systemPrompt(context: request.promptContext)
                            ],
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
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if object["error"] != nil {
                            continuation.finish(throwing: VoiceLLMProviderError.invalidResponse)
                            return
                        }
                        guard let choices = object["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String,
                              !content.isEmpty
                        else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generate(systemPrompt: String, userText: String) async throws -> String {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0,
            "max_tokens": 512,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
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
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw VoiceLLMProviderError.invalidResponse
        }
        return text
    }
}

import Foundation

struct OllamaModel: Identifiable, Equatable, Hashable {
    let name: String

    var id: String { name }
}

struct OllamaServiceClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = Self.nativeBaseURL(from: baseURL)
        self.session = session
    }

    static func nativeBaseURL(from baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/v1" {
            components.percentEncodedPath = ""
        } else if path.hasSuffix("/v1") {
            components.percentEncodedPath = String(path.dropLast(3))
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL
    }

    func listModels() async throws -> [OllamaModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"

        let data = try await Self.data(for: request, session: session)
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)
        return response.models.map { OllamaModel(name: $0.name) }
    }

    func pull(model: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": model,
            "stream": false
        ])

        _ = try await Self.data(for: request, session: session)
    }

    func delete(model: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/delete"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": model
        ])

        _ = try await Self.data(for: request, session: session)
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
}

private struct TagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

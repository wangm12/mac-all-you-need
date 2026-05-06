import Foundation
import Network

public actor DispatchServer {
    public struct Request: Equatable, Sendable {
        public let url: String
        public let title: String?
    }

    public typealias Handler = (Request) async -> Void

    private var listener: NWListener?
    private let token: String
    private let handler: Handler
    private let port: NWEndpoint.Port
    private let log = Logging.logger(for: "downloader", category: "dispatch")
    private let maxRequestBytes = 64 * 1024

    public init(port: UInt16 = 18765, token: String, handler: @escaping Handler) throws {
        self.token = token
        self.handler = handler
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: port)
        l.newConnectionHandler = { [weak self] conn in Task { await self?.accept(conn) } }
        l.start(queue: .global(qos: .utility))
        self.listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) async {
        conn.start(queue: .global(qos: .utility))
        readRequest(conn: conn, buffer: Data())
    }

    private func readRequest(conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, _ in
            Task { await self?.continueRead(conn: conn, buffer: buffer, chunk: data ?? Data(), isComplete: isComplete) }
        }
    }

    private func continueRead(conn: NWConnection, buffer: Data, chunk: Data, isComplete: Bool) async {
        var next = buffer
        next.append(chunk)
        guard next.count <= maxRequestBytes else { return await respond(conn, status: 413, body: "too large") }
        if let request = completeHTTPRequest(from: next) {
            return await handle(conn: conn, data: request)
        }
        guard !isComplete else { return await respond(conn, status: 400, body: "incomplete") }
        readRequest(conn: conn, buffer: next)
    }

    private func completeHTTPRequest(from data: Data) -> Data? {
        guard let raw = String(data: data, encoding: .utf8),
              let headerEnd = raw.range(of: "\r\n\r\n") else { return nil }
        let headerBytes = raw[..<headerEnd.upperBound].utf8.count
        let lines = raw[..<headerEnd.lowerBound].split(separator: "\r\n", omittingEmptySubsequences: false)
        let contentLength = lines
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        return data.count >= headerBytes + contentLength ? data : nil
    }

    private func handle(conn: NWConnection, data: Data) async {
        defer { conn.cancel() }
        guard let raw = String(data: data, encoding: .utf8) else {
            return await respond(conn, status: 400, body: "bad encoding")
        }
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.hasPrefix("POST /dispatch") else {
            return await respond(conn, status: 404, body: "")
        }
        let auth = lines
            .first(where: { $0.lowercased().hasPrefix("authorization:") })
            .map { String($0).split(separator: " ", maxSplits: 1).last.map(String.init) ?? "" } ?? ""
        guard auth == "Bearer \(token)" else { return await respond(conn, status: 401, body: "unauth") }
        let contentType = lines.first(where: { $0.lowercased().hasPrefix("content-type:") }) ?? ""
        guard contentType.lowercased().contains("application/json") else {
            return await respond(conn, status: 415, body: "json only")
        }
        guard let bodyStart = raw.range(of: "\r\n\r\n") else {
            return await respond(conn, status: 400, body: "no body")
        }
        let bodyData = Data(raw[bodyStart.upperBound...].utf8)
        struct Body: Codable { let url: String; let title: String? }
        guard let parsed = try? JSONDecoder().decode(Body.self, from: bodyData) else {
            return await respond(conn, status: 400, body: "invalid json")
        }
        guard let parsedURL = URL(string: parsed.url),
              ["http", "https"].contains(parsedURL.scheme?.lowercased() ?? "") else {
            return await respond(conn, status: 400, body: "unsupported url")
        }
        await handler(.init(url: parsed.url, title: parsed.title))
        await respond(conn, status: 200, body: "ok")
    }

    private func respond(_ conn: NWConnection, status: Int, body: String) async {
        let payload = "HTTP/1.1 \(status) \r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        await withCheckedContinuation { cont in
            conn.send(content: payload.data(using: .utf8)!, completion: .contentProcessed { _ in cont.resume() })
        }
    }
}

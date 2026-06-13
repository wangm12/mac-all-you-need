import Foundation
import Network

public actor DispatchServer {
    public struct Request: Equatable, Sendable {
        public let url: String
        public let title: String?
        public let mediaType: String?
        public let referer: String?
        public let headers: [String: String]?

        public init(
            url: String,
            title: String? = nil,
            mediaType: String? = nil,
            referer: String? = nil,
            headers: [String: String]? = nil
        ) {
            self.url = url
            self.title = title
            self.mediaType = mediaType
            self.referer = referer
            self.headers = headers
        }
    }

    public typealias Handler = (Request) async -> Void

    private var listener: NWListener?
    private let token: String
    private var extensionToken: String? = nil
    private let handler: Handler
    private let port: NWEndpoint.Port
    private let log = Logging.logger(for: "downloader", category: "dispatch")
    private let maxRequestBytes = 64 * 1024
    private var cookieSyncPending = false

    public init(port: UInt16 = 18765, token: String, extensionToken: String? = nil, handler: @escaping Handler) throws {
        self.token = token
        self.extensionToken = extensionToken
        self.handler = handler
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    public func start() throws {
        if extensionToken == nil { loadExtensionToken() }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: port)
        l.newConnectionHandler = { [weak self] conn in Task { await self?.accept(conn) } }
        l.start(queue: .global(qos: .utility))
        listener = l
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
        guard next.count <= maxRequestBytes else {
            return await respond(conn, status: 413, body: "too large", contentType: "text/plain")
        }
        if let request = completeHTTPRequest(from: next) {
            return await handle(conn: conn, data: request)
        }
        guard !isComplete else {
            return await respond(conn, status: 400, body: "incomplete", contentType: "text/plain")
        }
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

    public func requestCookieSync() {
        cookieSyncPending = true
    }

    private var extensionTokenURL: URL {
        AppGroup.containerURL().appendingPathComponent("extension.token")
    }

    private func loadExtensionToken() {
        guard extensionToken == nil else { return }
        guard let raw = try? String(contentsOf: extensionTokenURL, encoding: .utf8) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { extensionToken = trimmed }
    }

    private func persistExtensionToken(_ token: String) {
        extensionToken = token
        do {
            try token.data(using: .utf8)?.write(to: extensionTokenURL, options: .atomic)
        } catch {
            log.error("failed to persist extension token: \(error.localizedDescription)")
        }
    }

    private func handle(conn: NWConnection, data: Data) async {
        defer { conn.cancel() }
        guard let raw = String(data: data, encoding: .utf8) else {
            return await respond(conn, status: 400, body: "bad encoding", contentType: "text/plain")
        }
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else {
            return await respond(conn, status: 400, body: "bad request", contentType: "text/plain")
        }
        let methodPath = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard methodPath.count >= 2 else {
            return await respond(conn, status: 400, body: "bad request", contentType: "text/plain")
        }
        let method = String(methodPath[0]).uppercased()
        let path = String(methodPath[1]).split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"

        if method == "OPTIONS" {
            return await respond(conn, status: 204, body: "", contentType: "text/plain")
        }

        if method == "GET", path == "/ping" {
            // An empty/absent token is a pure reachability probe (used by the
            // app's own "App reachable" check). It registers nothing.
            guard let tok = headerValue(from: lines, name: "x-mayn-token"), !tok.isEmpty else {
                return await respond(conn, status: 200, body: #"{"ok":true,"app":"MacAllYouNeed"}"#, contentType: "application/json")
            }
            if let registered = extensionToken {
                // First-write-wins: a registered token can never be overwritten.
                // A different token is a hijack attempt and is rejected.
                guard tok == registered else {
                    return await respond(conn, status: 409, body: #"{"error":"already registered"}"#, contentType: "application/json")
                }
            } else {
                persistExtensionToken(tok)
            }
            return await respond(conn, status: 200, body: #"{"ok":true,"app":"MacAllYouNeed"}"#, contentType: "application/json")
        }

        // The /dispatch route authenticates with its own bearer token (below) and
        // is for external callers that do not hold the extension token. It must
        // bypass the extension-token guard.
        let isBearerDispatch = (method == "POST" && path == "/dispatch")

        // FAIL CLOSED: every non-/ping endpoint (other than bearer /dispatch)
        // requires a registered token, and the incoming request must carry a
        // matching X-MAYN-Token. Before any token has been registered, all of
        // these endpoints are rejected so a local process can never read/poison
        // cookies or inject jobs.
        if !isBearerDispatch {
            guard let registered = extensionToken else {
                return await respond(conn, status: 401, body: #"{"error":"not registered"}"#, contentType: "application/json")
            }
            let incoming = headerValue(from: lines, name: "x-mayn-token") ?? ""
            guard incoming == registered else {
                return await respond(conn, status: 401, body: #"{"error":"unauthorized"}"#, contentType: "application/json")
            }
        }

        if method == "GET", path == "/cookie-sync-poll" {
            let body = #"{"pending":\#(cookieSyncPending ? "true" : "false")}"#
            return await respond(conn, status: 200, body: body, contentType: "application/json")
        }

        if method == "GET", path == "/cookie-sync-landing" {
            let html = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>Cookie sync requested. Keep this page open in Chrome with extension installed.</body></html>
            """
            return await respond(conn, status: 200, body: html, contentType: "text/html; charset=utf-8")
        }

        if method == "POST", path == "/cookies" {
            guard let bodyData = bodyData(from: raw),
                  let cookies = try? JSONDecoder().decode([ChromeSyncCookie].self, from: bodyData)
            else {
                return await respond(conn, status: 400, body: #"{"error":"invalid cookies payload"}"#, contentType: "application/json")
            }
            do {
                let count = try saveCookies(cookies)
                cookieSyncPending = false
                let body = #"{"ok":true,"count":\#(count)}"#
                return await respond(conn, status: 200, body: body, contentType: "application/json")
            } catch {
                log.error("cookie sync failed: \(error.localizedDescription)")
                return await respond(conn, status: 500, body: #"{"error":"cookie sync failed"}"#, contentType: "application/json")
            }
        }

        if method == "POST", path == "/download" || path == "/dispatch" {
            guard let bodyData = bodyData(from: raw) else {
                return await respond(conn, status: 400, body: "missing body", contentType: "text/plain")
            }
            if path == "/dispatch" {
                let auth = lines
                    .first(where: { $0.lowercased().hasPrefix("authorization:") })
                    .map { String($0).split(separator: " ", maxSplits: 1).last.map(String.init) ?? "" } ?? ""
                guard auth == "Bearer \(token)" else {
                    return await respond(conn, status: 401, body: "unauth", contentType: "text/plain")
                }
            }
            guard let parsed = try? JSONDecoder().decode(DownloadBody.self, from: bodyData) else {
                return await respond(conn, status: 400, body: "invalid json", contentType: "text/plain")
            }
            let urlList: [String] = if let urls = parsed.urls, !urls.isEmpty {
                urls
            } else if let url = parsed.url {
                [url]
            } else {
                []
            }
            guard !urlList.isEmpty else {
                return await respond(conn, status: 400, body: "missing url", contentType: "text/plain")
            }
            for url in urlList {
                guard let parsedURL = URL(string: url),
                      ["http", "https"].contains(parsedURL.scheme?.lowercased() ?? "")
                else {
                    return await respond(conn, status: 400, body: "unsupported url", contentType: "text/plain")
                }
                await handler(.init(
                    url: url,
                    title: parsed.title,
                    mediaType: parsed.type?.nilIfEmpty,
                    referer: parsed.referer?.nilIfEmpty,
                    headers: parsed.headers
                ))
            }
            return await respond(conn, status: 200, body: #"{"ok":true}"#, contentType: "application/json")
        }

        await respond(conn, status: 404, body: "not found", contentType: "text/plain")
    }

    private func bodyData(from raw: String) -> Data? {
        guard let bodyStart = raw.range(of: "\r\n\r\n") else { return nil }
        return Data(raw[bodyStart.upperBound...].utf8)
    }

    private func headerValue(from lines: [Substring], name: String) -> String? {
        let prefix = name.lowercased() + ":"
        guard let line = lines.first(where: { $0.lowercased().hasPrefix(prefix) }) else { return nil }
        return String(line).dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    private func respond(_ conn: NWConnection, status: Int, body: String, contentType: String) async {
        let payload = """
        HTTP/1.1 \(status)
        Content-Type: \(contentType)
        Access-Control-Allow-Origin: *
        Access-Control-Allow-Methods: GET, POST, OPTIONS
        Access-Control-Allow-Headers: Content-Type, Authorization, X-MAYN-Token
        Content-Length: \(body.utf8.count)
        Connection: close

        \(body)
        """
        await withCheckedContinuation { cont in
            conn.send(content: payload.data(using: .utf8)!, completion: .contentProcessed { _ in cont.resume() })
        }
    }
}

private struct DownloadBody: Codable {
    let url: String?
    let urls: [String]?
    let title: String?
    let type: String?
    let referer: String?
    let headers: [String: String]?
}

private struct ChromeSyncCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let expirationDate: Double?
}

private extension DispatchServer {
    func saveCookies(_ cookies: [ChromeSyncCookie]) throws -> Int {
        let cookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-extension-cookies.txt")
        try FileManager.default.createDirectory(
            at: cookieFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            let host = cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { continue }
            let includeSubdomains = host.hasPrefix(".") ? "TRUE" : "FALSE"
            let secure = cookie.secure ? "TRUE" : "FALSE"
            let expires = Int(cookie.expirationDate ?? 0)
            lines.append([
                host,
                includeSubdomains,
                cookie.path.isEmpty ? "/" : cookie.path,
                secure,
                String(expires),
                cookie.name,
                cookie.value
            ].joined(separator: "\t"))
        }
        let output = lines.joined(separator: "\n") + "\n"
        try output.write(to: cookieFile, atomically: true, encoding: .utf8)
        AppGroupSettings.defaults.set("synced", forKey: "downloadExtensionState")
        AppGroupSettings.defaults.set(Date().timeIntervalSince1970, forKey: "downloadExtensionSyncedAt")
        return max(lines.count - 1, 0)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

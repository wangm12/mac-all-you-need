@testable import Core
import XCTest

final class DispatchTokenTests: XCTestCase {
    func testRotateProducesDifferentTokens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tok-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("token")
        let t1 = try DispatchToken.rotate(at: url)
        let t2 = try DispatchToken.rotate(at: url)
        XCTAssertNotEqual(t1, t2)
    }

    func testReadReturnsLastRotated() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tok2-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("token")
        let last = try DispatchToken.rotate(at: url)
        XCTAssertEqual(try DispatchToken.read(at: url), last)
    }
}

final class DispatchServerTests: XCTestCase {
    // Pre-seeded extension token used by every test that hits authenticated endpoints.
    private let extToken = "test-ext-token"

    func testAcceptsValidToken() async throws {
        let received = expectation(description: "received")
        let server = try DispatchServer(port: 18999, token: "secret") { req in
            XCTAssertEqual(req.url, "https://x.com")
            XCTAssertNil(req.mediaType)
            received.fulfill()
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let body = Data(#"{"url":"https://x.com"}"#.utf8)
        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18999/dispatch")))
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [received], timeout: 3)
    }

    func testRejectsBadToken() async throws {
        let server = try DispatchServer(port: 18998, token: "secret") { _ in XCTFail("should not call") }
        try await server.start()
        defer { Task { await server.stop() } }
        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18998/dispatch")))
        req.httpMethod = "POST"; req.httpBody = Data("{}".utf8)
        req.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 401)
    }

    func testDownloadEndpointAcceptsExtensionPayload() async throws {
        let received = expectation(description: "received")
        let server = try DispatchServer(port: 18997, token: "secret", extensionToken: extToken) { req in
            XCTAssertEqual(req.url, "https://cdn.example.com/v.m3u8")
            XCTAssertEqual(req.mediaType, "hls")
            XCTAssertEqual(req.referer, "https://example.com/page")
            XCTAssertEqual(req.headers?["Origin"], "https://example.com")
            received.fulfill()
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let body = Data(#"{"url":"https://cdn.example.com/v.m3u8","type":"hls","referer":"https://example.com/page","headers":{"Origin":"https://example.com"}}"#.utf8)
        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18997/download")))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [received], timeout: 3)
    }

    func testDownloadEndpointAcceptsURLsArray() async throws {
        let received = expectation(description: "received array")
        received.expectedFulfillmentCount = 2
        var seen: [String] = []
        let server = try DispatchServer(port: 18992, token: "secret", extensionToken: extToken) { req in
            seen.append(req.url)
            received.fulfill()
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let body = Data(#"{"urls":["https://example.com/a","https://example.com/b"]}"#.utf8)
        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18992/download")))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(seen, ["https://example.com/a", "https://example.com/b"])
    }

    func testBulkEnqueueRespondsBeforeHandlerCompletes() async throws {
        let handlerStarted = expectation(description: "handler started")
        let gate = DispatchSemaphore(value: 0)
        let server = try DispatchServer(port: 18991, token: "secret", extensionToken: extToken) { req in
            XCTAssertEqual(req.action, .bulkEnqueue)
            handlerStarted.fulfill()
            _ = gate.wait(timeout: .now() + 5)
        }
        try await server.start()
        defer {
            gate.signal()
            Task { await server.stop() }
        }

        let body = Data(#"{"action":"bulkEnqueue","title":"Bulk","entries":[{"pageURL":"https://example.com/1","title":"One","channel":"","thumbnailURL":null,"durationSeconds":null,"playlistIndex":1}]}"#.utf8)
        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18991/dispatch")))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let start = Date()
        let (_, resp) = try await URLSession.shared.data(for: req)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [handlerStarted], timeout: 3)
    }

    func testDownloadEndpointRejectsUnsupportedURLScheme() async throws {
        let server = try DispatchServer(port: 18990, token: "secret", extensionToken: extToken) { _ in
            XCTFail("should not call handler for unsupported URL")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let body = Data(#"{"url":"file:///tmp/video.mp4"}"#.utf8)
        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18990/download")))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 400)
    }

    func testPingEndpoint() async throws {
        let server = try DispatchServer(port: 18996, token: "secret") { _ in XCTFail("should not call") }
        try await server.start()
        defer { Task { await server.stop() } }

        let (_, resp) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: "http://127.0.0.1:18996/ping")))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
    }

    func testCookieSyncPollDefaultsFalse() async throws {
        let server = try DispatchServer(port: 18995, token: "secret", extensionToken: extToken) { _ in XCTFail("should not call") }
        try await server.start()
        defer { Task { await server.stop() } }

        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18995/cookie-sync-poll")))
        req.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (data, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"pending":false}"#)
    }

    func testCookieSyncLandingReturnsHTML() async throws {
        let server = try DispatchServer(port: 18994, token: "secret", extensionToken: extToken) { _ in XCTFail("should not call") }
        try await server.start()
        defer { Task { await server.stop() } }

        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18994/cookie-sync-landing")))
        req.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (data, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("id=\"status\""))
        XCTAssertTrue(body.contains("Mac All You Need Companion"))
    }

    func testCookieSyncLandingWorksWithoutToken() async throws {
        let server = try DispatchServer(port: 18988, token: "secret", extensionToken: extToken) { _ in
            XCTFail("should not call")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let (data, resp) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: "http://127.0.0.1:18988/cookie-sync-landing")))
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("id=\"status\""))
        XCTAssertTrue(body.contains("Mac All You Need Companion"))
    }

    func testCookiesStillRequiresToken() async throws {
        let server = try DispatchServer(port: 18987, token: "secret", extensionToken: extToken) { _ in
            XCTFail("should not call")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        var post = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18987/cookies")))
        post.httpMethod = "POST"
        post.httpBody = Data("[]".utf8)
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.data(for: post)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 401)
    }

    func testResetExtensionTokenAllowsReregistration() async throws {
        let tokenA = "token-a"
        let tokenB = "token-b"
        let server = try DispatchServer(port: 18986, token: "secret", extensionToken: tokenA) { _ in
            XCTFail("should not call")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        var conflictReq = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18986/ping")))
        conflictReq.setValue(tokenB, forHTTPHeaderField: "X-MAYN-Token")
        let (_, conflictResp) = try await URLSession.shared.data(for: conflictReq)
        XCTAssertEqual((conflictResp as? HTTPURLResponse)?.statusCode, 409)

        await server.resetExtensionToken()

        var registerReq = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18986/ping")))
        registerReq.setValue(tokenB, forHTTPHeaderField: "X-MAYN-Token")
        let (_, registerResp) = try await URLSession.shared.data(for: registerReq)
        XCTAssertEqual((registerResp as? HTTPURLResponse)?.statusCode, 200)
    }

    func testCompanionResetClearsRegistration() async throws {
        let tokenA = "token-a"
        let tokenB = "token-b"
        let server = try DispatchServer(port: 18985, token: "secret", extensionToken: tokenA) { _ in
            XCTFail("should not call")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        var reset = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18985/companion-reset")))
        reset.httpMethod = "POST"
        let (_, resetResp) = try await URLSession.shared.data(for: reset)
        XCTAssertEqual((resetResp as? HTTPURLResponse)?.statusCode, 200)

        var registerReq = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18985/ping")))
        registerReq.setValue(tokenB, forHTTPHeaderField: "X-MAYN-Token")
        let (_, registerResp) = try await URLSession.shared.data(for: registerReq)
        XCTAssertEqual((registerResp as? HTTPURLResponse)?.statusCode, 200)
    }

    func testOptionsReturnsNoContent() async throws {
        let server = try DispatchServer(port: 18993, token: "secret") { _ in XCTFail("should not call") }
        try await server.start()
        defer { Task { await server.stop() } }

        var req = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18993/download")))
        req.httpMethod = "OPTIONS"
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 204)
    }

    func testCookieSyncPendingThenClearsAfterCookiesPost() async throws {
        let server = try DispatchServer(port: 18991, token: "secret", extensionToken: extToken) { _ in XCTFail("should not call") }
        await server.requestCookieSync()
        try await server.start()
        defer { Task { await server.stop() } }

        var pollReq = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18991/cookie-sync-poll")))
        pollReq.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")

        let (beforeData, beforeResp) = try await URLSession.shared.data(for: pollReq)
        XCTAssertEqual((beforeResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: beforeData, encoding: .utf8), #"{"pending":true}"#)

        let cookiePayload = """
        [{
          "name":"sid",
          "value":"abc",
          "domain":".example.com",
          "path":"/",
          "secure":true,
          "httpOnly":false,
          "expirationDate":1999999999
        }]
        """
        var post = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18991/cookies")))
        post.httpMethod = "POST"
        post.httpBody = Data(cookiePayload.utf8)
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (postData, postResp) = try await URLSession.shared.data(for: post)
        XCTAssertEqual((postResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue((String(data: postData, encoding: .utf8) ?? "").contains(#""ok":true"#))
        XCTAssertTrue((String(data: postData, encoding: .utf8) ?? "").contains(#""count":1"#))

        let (afterData, afterResp) = try await URLSession.shared.data(for: pollReq)
        XCTAssertEqual((afterResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: afterData, encoding: .utf8), #"{"pending":false}"#)
    }

    func testCookiesEndpointWritesNetscapeCookieFile() async throws {
        let server = try DispatchServer(port: 18989, token: "secret", extensionToken: extToken) { _ in XCTFail("should not call") }
        try await server.start()
        defer { Task { await server.stop() } }

        let cookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-extension-cookies.txt")
        try? FileManager.default.removeItem(at: cookieFile)

        let cookiePayload = """
        [{
          "name":"sid",
          "value":"abc",
          "domain":".example.com",
          "path":"/",
          "secure":true,
          "httpOnly":false,
          "expirationDate":1999999999
        }]
        """
        var post = try URLRequest(url: XCTUnwrap(URL(string: "http://127.0.0.1:18989/cookies")))
        post.httpMethod = "POST"
        post.httpBody = Data(cookiePayload.utf8)
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue(extToken, forHTTPHeaderField: "X-MAYN-Token")
        let (_, postResp) = try await URLSession.shared.data(for: post)
        XCTAssertEqual((postResp as? HTTPURLResponse)?.statusCode, 200)

        let fileText = try String(contentsOf: cookieFile, encoding: .utf8)
        let lines = fileText.split(separator: "\n")
        XCTAssertFalse(lines.isEmpty)
        XCTAssertEqual(String(lines[0]), "# Netscape HTTP Cookie File")
        XCTAssertTrue(lines.dropFirst().contains { line in
            let columns = line.split(separator: "\t")
            return columns.count == 7
                && columns[0] == ".example.com"
                && columns[5] == "sid"
                && columns[6] == "abc"
        })
    }
}

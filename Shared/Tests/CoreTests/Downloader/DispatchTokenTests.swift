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
    func testAcceptsValidToken() async throws {
        let received = expectation(description: "received")
        let server = try DispatchServer(port: 18999, token: "secret") { req in
            XCTAssertEqual(req.url, "https://x.com")
            received.fulfill()
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let body = Data(#"{"url":"https://x.com"}"#.utf8)
        var req = URLRequest(url: URL(string: "http://127.0.0.1:18999/dispatch")!)
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
        var req = URLRequest(url: URL(string: "http://127.0.0.1:18998/dispatch")!)
        req.httpMethod = "POST"; req.httpBody = Data("{}".utf8)
        req.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 401)
    }
}

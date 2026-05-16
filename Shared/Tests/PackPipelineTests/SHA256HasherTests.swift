import XCTest
@testable import PackPipeline

final class SHA256HasherTests: XCTestCase {
    func testHashOfHelloWorld() throws {
        let data = "hello world".data(using: .utf8)!
        let hex = SHA256Hasher.hex(of: data)
        XCTAssertEqual(hex, "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    func testStreamingMatchesOneShot() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha256-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let payload = Data(repeating: 0x41, count: 1_000_000)
        try payload.write(to: tmp)

        let oneShot = SHA256Hasher.hex(of: payload)
        let streamed = try SHA256Hasher.hex(ofFileAt: tmp)
        XCTAssertEqual(oneShot, streamed)
    }
}

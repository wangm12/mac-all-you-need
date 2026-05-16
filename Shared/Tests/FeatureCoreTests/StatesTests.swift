import XCTest
@testable import FeatureCore

final class StatesTests: XCTestCase {
    func testAssetStateCases() {
        // smoke: ensure all cases compile and are equatable
        let a: AssetState = .notRequired
        let b: AssetState = .notDownloaded
        let c: AssetState = .downloading(progress: 0.5)
        let d: AssetState = .downloadFailed(reason: "disk full")
        let e: AssetState = .present(version: "1.0.0")

        XCTAssertEqual(a, .notRequired)
        XCTAssertEqual(b, .notDownloaded)
        XCTAssertEqual(c, .downloading(progress: 0.5))
        XCTAssertEqual(d, .downloadFailed(reason: "disk full"))
        XCTAssertEqual(e, .present(version: "1.0.0"))
        XCTAssertNotEqual(c, .downloading(progress: 0.6))
    }

    func testActivationStateCases() {
        XCTAssertEqual(ActivationState.disabled, .disabled)
        XCTAssertEqual(ActivationState.enabled, .enabled)
        XCTAssertNotEqual(ActivationState.disabled, .enabled)
    }

    func testAssetStateCodableRoundTrip() throws {
        let cases: [AssetState] = [
            .notRequired,
            .notDownloaded,
            .downloading(progress: 0.42),
            .downloadFailed(reason: "SHA mismatch"),
            .present(version: "1.0.0"),
        ]
        for value in cases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AssetState.self, from: data)
            XCTAssertEqual(value, decoded, "round-trip failed for \(value)")
        }
    }

    func testActivationStateCodableRoundTrip() throws {
        for value in [ActivationState.disabled, .enabled] {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ActivationState.self, from: data)
            XCTAssertEqual(value, decoded)
        }
    }
}

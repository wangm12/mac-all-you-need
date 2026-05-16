import XCTest
@testable import FeatureCore

final class FeatureRuntimeStateTests: XCTestCase {
    func testInitialDefault() {
        let state = FeatureRuntimeState.initialDefault(assetRequired: true)
        XCTAssertEqual(state.assetState, .notDownloaded)
        XCTAssertEqual(state.activationState, .disabled)
    }

    func testInitialDefaultForSwiftOnly() {
        let state = FeatureRuntimeState.initialDefault(assetRequired: false)
        XCTAssertEqual(state.assetState, .notRequired)
        XCTAssertEqual(state.activationState, .disabled)
    }

    func testCanActivateOnlyWhenAssetReady() {
        let states: [(FeatureRuntimeState, Bool)] = [
            (.init(assetState: .notRequired, activationState: .disabled), true),
            (.init(assetState: .present(version: "1.0"), activationState: .disabled), true),
            (.init(assetState: .notDownloaded, activationState: .disabled), false),
            (.init(assetState: .downloading(progress: 0), activationState: .disabled), false),
            (.init(assetState: .downloadFailed(reason: ""), activationState: .disabled), false),
        ]
        for (state, expected) in states {
            XCTAssertEqual(state.canActivate, expected, "canActivate wrong for \(state)")
        }
    }

    func testCodableRoundTrip() throws {
        let cases: [FeatureRuntimeState] = [
            .init(assetState: .notRequired, activationState: .enabled),
            .init(assetState: .present(version: "2.0"), activationState: .disabled),
            .init(assetState: .downloading(progress: 0.7), activationState: .disabled),
        ]
        for state in cases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(FeatureRuntimeState.self, from: data)
            XCTAssertEqual(state, decoded)
        }
    }
}

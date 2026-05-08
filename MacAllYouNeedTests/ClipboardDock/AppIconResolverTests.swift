@testable import MacAllYouNeed
import AppKit
import XCTest

@MainActor
final class AppIconResolverTests: XCTestCase {
    func testReturnsIconForKnownBundleID() {
        let resolver = AppIconResolver()
        let icon = resolver.icon(for: "com.apple.Finder")
        XCTAssertNotNil(icon)
    }

    func testReturnsNilForUnknownBundleID() {
        let resolver = AppIconResolver()
        XCTAssertNil(resolver.icon(for: "com.nonexistent.example.app.\(UUID().uuidString)"))
    }

    func testCachesByBundleID() {
        let resolver = AppIconResolver()
        let first = resolver.icon(for: "com.apple.Finder")
        let second = resolver.icon(for: "com.apple.Finder")
        XCTAssertTrue(first === second, "icon should be returned from cache")
    }

    func testDisplayNameReturnsBundleNameForKnownApp() {
        let resolver = AppIconResolver()
        let name = resolver.displayName(for: "com.apple.Finder")
        XCTAssertEqual(name, "Finder")
    }

    func testDisplayNameFallsBackToBundleID() {
        let resolver = AppIconResolver()
        let bundleID = "com.nonexistent.\(UUID().uuidString)"
        XCTAssertEqual(resolver.displayName(for: bundleID), bundleID)
    }
}

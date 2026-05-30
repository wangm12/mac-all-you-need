@testable import MacAllYouNeed
import FeatureCore
import XCTest

final class ClipboardSmartTextDescriptorTests: XCTestCase {
    func testDescriptorBasics() {
        let d = ClipboardSmartTextDescriptor.descriptor()
        XCTAssertEqual(d.id, .clipboardSmartText)
        XCTAssertTrue(d.requiredPermissions.isEmpty)
        XCTAssertNotNil(d.settingsTabFactory)
        XCTAssertFalse(d.displayName.isEmpty)
    }

    func testRegisteredInRegistry() {
        let registry = FeatureRegistryProvider.makeRegistry()
        XCTAssertTrue(registry.descriptors.contains { $0.id == .clipboardSmartText })
    }
}

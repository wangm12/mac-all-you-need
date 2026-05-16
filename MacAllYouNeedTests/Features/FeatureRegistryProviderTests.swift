import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FeatureRegistryProviderTests: XCTestCase {
    func testProviderReturnsAllFourFeatures() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let ids = registry.descriptors.map(\.id)
        XCTAssertEqual(ids, [.clipboard, .folderPreview, .downloader, .voice],
                       "Registry order is contractual; UI iterates this order.")
    }

    func testEachDescriptorHasDisplayMetadata() {
        let registry = FeatureRegistryProvider.makeRegistry()
        for descriptor in registry.descriptors {
            XCTAssertFalse(descriptor.displayName.isEmpty, "\(descriptor.id) missing displayName")
            XCTAssertFalse(descriptor.icon.isEmpty, "\(descriptor.id) missing icon")
            XCTAssertFalse(descriptor.summary.isEmpty, "\(descriptor.id) missing summary")
        }
    }
}

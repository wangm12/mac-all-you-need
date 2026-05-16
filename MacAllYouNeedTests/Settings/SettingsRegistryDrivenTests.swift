import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class SettingsRegistryDrivenTests: XCTestCase {
    func testTabListIncludesAllFeaturesWithFactories() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let tabs = SettingsRoot.featureTabs(registry: registry)
        let ids = tabs.map(\.0)
        XCTAssertEqual(
            ids, [.clipboard, .folderPreview, .downloader, .voice],
            "feature tabs must follow registry order and include all features with factories"
        )
    }

    func testFeatureTabsReturnAnyViewForEachFactory() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let tabs = SettingsRoot.featureTabs(registry: registry)
        XCTAssertEqual(tabs.count, registry.descriptors.filter { $0.settingsTabFactory != nil }.count,
                       "featureTabs must return one entry per descriptor with a settingsTabFactory")
    }
}

import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class SettingsRegistryDrivenTests: XCTestCase {
    func testTabListIncludesAllFeaturesWithFactories() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let states = Dictionary(uniqueKeysWithValues: registry.descriptors.map {
            ($0.id, FeatureRuntimeState.initialDefault(assetRequired: $0.requiresAsset))
        })
        let tabs = SettingsRoot.featureTabs(registry: registry, states: states)
        let ids = tabs.map(\.0)
        let expectedIDs = registry.descriptors
            .filter { $0.settingsTabFactory != nil }
            .map(\.id)
        XCTAssertEqual(ids, expectedIDs, "feature tabs must follow registry order.")
    }

    func testFeatureTabsReturnAnyViewForEachFactory() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let states = Dictionary(uniqueKeysWithValues: registry.descriptors.map {
            ($0.id, FeatureRuntimeState.initialDefault(assetRequired: $0.requiresAsset))
        })
        let tabs = SettingsRoot.featureTabs(registry: registry, states: states)
        XCTAssertEqual(tabs.count, registry.descriptors.filter { $0.settingsTabFactory != nil }.count,
                       "featureTabs must return one entry per descriptor with a settingsTabFactory")
    }
}

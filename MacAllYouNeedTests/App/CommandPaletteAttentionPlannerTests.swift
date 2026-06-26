@testable import MacAllYouNeed
import FeatureCore
import XCTest

@MainActor
final class CommandPaletteAttentionPlannerTests: XCTestCase {
    func testSnapshotFlagsVoiceSetupWhenVoiceEnabledAndPermissionsMissing() {
        let registry = FeatureRegistry(descriptors: [VoiceDescriptor.descriptor()])
        let state = FeatureRuntimeState(
            assetState: .present(version: "test"),
            activationState: .enabled
        )
        let snapshot = CommandPaletteAttentionPlanner.snapshot(
            registry: registry,
            stateFor: { _ in state },
            failedDownloadCount: 0,
            orphanCacheCount: 0
        )
        XCTAssertTrue(snapshot.voiceSetupNeeded)
        XCTAssertFalse(snapshot.missingPermissions.isEmpty)
    }

    func testAttentionItemsIncludePermissionsAndOrphans() {
        let context = CommandPaletteContext(
            destination: .dashboard,
            hotkeys: [:],
            voiceShortcut: "⌥Space",
            voiceMode: .toggle,
            failedDownloadCount: 2,
            enabledDestinations: [.dashboard, .downloads, .settings],
            attention: CommandPaletteAttentionSnapshot(
                failedDownloadCount: 2,
                orphanCacheCount: 3,
                missingPermissions: [.microphone],
                permissionsAttentionTitle: "Grant Microphone",
                voiceSetupNeeded: false
            )
        )
        let section = CommandPaletteCatalog.sections(context: context)
            .first(where: { $0.section == .attention })
        let titles = section?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains(where: { $0.contains("downloads needing attention") }))
        XCTAssertTrue(titles.contains("Review 3 orphan caches"))
        XCTAssertTrue(titles.contains(where: { $0.contains("Grant Microphone") }))
    }
}

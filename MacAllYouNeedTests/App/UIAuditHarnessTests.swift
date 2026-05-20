@testable import MacAllYouNeed
import Core
import XCTest

final class UIAuditHarnessTests: XCTestCase {
    func testAuditLaunchModeRequiresExplicitTruthyEnvironmentValue() {
        XCTAssertFalse(UIAuditLaunchMode.isEnabled(environment: [:]))
        XCTAssertFalse(UIAuditLaunchMode.isEnabled(environment: [UIAuditLaunchMode.environmentKey: "0"]))
        XCTAssertFalse(UIAuditLaunchMode.isEnabled(environment: [UIAuditLaunchMode.environmentKey: "false"]))

        XCTAssertTrue(UIAuditLaunchMode.isEnabled(environment: [UIAuditLaunchMode.environmentKey: "1"]))
        XCTAssertTrue(UIAuditLaunchMode.isEnabled(environment: [UIAuditLaunchMode.environmentKey: "true"]))
        XCTAssertTrue(UIAuditLaunchMode.isEnabled(environment: [UIAuditLaunchMode.environmentKey: "YES"]))
    }

    func testAuditRuntimeConfigurationIsolatesContainerAndDefaults() throws {
        let configuration = try UIAuditLaunchMode.runtimeConfiguration(environment: [
            UIAuditLaunchMode.environmentKey: "1"
        ])

        XCTAssertTrue(configuration.appGroupContainerURL.path.contains("MacAllYouNeed-UIAudit"))
        XCTAssertTrue(configuration.defaultsSuiteName.hasPrefix("com.macallyouneed.ui-audit."))
        XCTAssertEqual(configuration.liveServicePolicy, .disabled)
    }

    func testAuditRuntimeConfigurationUsesProvidedIsolationOverrides() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("mayn-audit-test-\(UUID().uuidString)", isDirectory: true)
        let suite = "com.macallyouneed.audit-test.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: container)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        let configuration = try UIAuditLaunchMode.runtimeConfiguration(environment: [
            UIAuditLaunchMode.environmentKey: "1",
            AppGroup.containerOverrideEnvironmentKey: container.path,
            AppGroupSettings.defaultsSuiteOverrideEnvironmentKey: suite
        ])

        XCTAssertEqual(configuration.appGroupContainerURL, container)
        XCTAssertEqual(configuration.defaultsSuiteName, suite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: container.path))
    }

    func testAuditCatalogHasSmallPhaseOneScenarioSetWithStableIDs() {
        let scenarios = UIAuditSurfaceCatalog.phaseOneScenarios
        let ids = scenarios.map(\.id)

        XCTAssertGreaterThanOrEqual(scenarios.count, 15)
        XCTAssertLessThanOrEqual(scenarios.count, 25)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Set(ids).isSuperset(of: UIAuditSurfaceCatalog.requiredPhaseOneScenarioIDs))
    }

    func testAuditScenariosCarryCaptureMetadataAndNativeSurfaceMode() {
        for scenario in UIAuditSurfaceCatalog.phaseOneScenarios {
            XCTAssertFalse(scenario.surface.isEmpty, scenario.id)
            XCTAssertFalse(scenario.route.isEmpty, scenario.id)
            XCTAssertFalse(scenario.state.isEmpty, scenario.id)
            XCTAssertTrue(scenario.screenshotFilename.hasSuffix(".png"), scenario.id)
            XCTAssertEqual(scenario.captureStatus, .pending, scenario.id)
            XCTAssertNil(scenario.notCapturedReason, scenario.id)
            XCTAssertGreaterThanOrEqual(scenario.stabilityWaitHintMilliseconds, 0, scenario.id)
        }

        XCTAssertTrue(UIAuditSurfaceCatalog.phaseOneScenarios.contains {
            $0.nativeRenderingMode == .simulatedEquivalent
        })
        XCTAssertTrue(UIAuditSurfaceCatalog.phaseOneScenarios.contains {
            $0.nativeRenderingMode == .nativeIsolated
        })
    }

    func testManifestIncludesReproducibilityMetadata() {
        let manifest = UIAuditManifest.make(
            runID: "2026-05-20-1200",
            gitSha: "abc123",
            buildConfiguration: "Debug",
            appVersion: "1.0",
            dataProfileID: "phase-one-demo",
            colorScheme: "light",
            windowSize: CGSize(width: 980, height: 680),
            reducedMotion: false,
            scenarios: UIAuditSurfaceCatalog.phaseOneScenarios
        )

        XCTAssertEqual(manifest.gitSha, "abc123")
        XCTAssertEqual(manifest.buildConfiguration, "Debug")
        XCTAssertEqual(manifest.dataProfileID, "phase-one-demo")
        XCTAssertEqual(manifest.windowSize.width, 980)
        XCTAssertEqual(manifest.windowSize.height, 680)
        XCTAssertEqual(manifest.scenarios.count, UIAuditSurfaceCatalog.phaseOneScenarios.count)
    }

    func testArtifactWriterCreatesManifestAndIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mayn-audit-artifacts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = UIAuditManifest.make(
            runID: "2026-05-20-1200",
            gitSha: "abc123",
            buildConfiguration: "Debug",
            appVersion: "1.0",
            dataProfileID: "phase-one-demo",
            colorScheme: "system",
            windowSize: CGSize(width: 980, height: 680),
            reducedMotion: false,
            scenarios: UIAuditSurfaceCatalog.phaseOneScenarios
        )

        let directory = try UIAuditArtifactWriter.write(manifest: manifest, rootDirectory: root)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let indexURL = directory.appendingPathComponent("index.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        let decoded = try JSONDecoder().decode(UIAuditManifest.self, from: Data(contentsOf: manifestURL))
        let index = try String(contentsOf: indexURL, encoding: .utf8)

        XCTAssertEqual(decoded, manifest)
        XCTAssertTrue(index.contains("dashboard.overview.enabled"))
        XCTAssertTrue(index.contains("phase-one-demo"))
    }
}

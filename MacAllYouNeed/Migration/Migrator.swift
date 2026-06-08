import Core
import CryptoKit
import FeatureCore
import Foundation

/// One-time upgrade orchestrator. Idempotent via `MigrationSentinel`.
struct Migrator {
    typealias AssetProbe = (FeatureID, FeatureDescriptor) throws -> MigrationDecisionMatrix.AssetPresence

    let defaults: UserDefaults
    let detector: PriorUsageDetector
    let assetProbe: AssetProbe
    let featuresBaseDir: URL

    init(
        defaults: UserDefaults = AppGroupSettings.defaults,
        detector: PriorUsageDetector,
        assetProbe: AssetProbe? = nil,
        featuresBaseDir: URL = AppGroup.containerURL().appendingPathComponent("Features", isDirectory: true)
    ) {
        self.defaults = defaults
        self.detector = detector
        self.featuresBaseDir = featuresBaseDir
        let baseDir = featuresBaseDir
        self.assetProbe = assetProbe ?? { id, descriptor in
            try Migrator.probeOnDisk(
                featureID: id,
                descriptor: descriptor,
                featuresBaseDir: baseDir,
                manifest: Migrator.loadBundledManifest()
            )
        }
    }

    /// Entry point. Returns `.noop` immediately if the sentinel is already set.
    func migrateIfNeeded(featureRuntime: FeatureRuntime) async throws -> MigrationReport {
        if MigrationSentinel.hasMigrated(defaults: defaults) {
            return .noop
        }

        let registry = await featureRuntime.registry
        let manager = await featureRuntime.manager

        // Detect usage — on error, fall back to "all features enabled" per spec § 7.2
        let usage: [FeatureID: PriorUsageLevel]
        do {
            usage = try detector.detect()
        } catch {
            NSLog("[Migrator] detection failed (\(error)); falling back to all-enabled per spec § 7.2")
            usage = Dictionary(uniqueKeysWithValues: registry.descriptors.map { ($0.id, PriorUsageLevel.directEvidence) })
        }

        var outcomes: [FeatureID: MigrationReport.Outcome] = [:]

        for descriptor in registry.descriptors {
            let presence: MigrationDecisionMatrix.AssetPresence = descriptor.requiresAsset
                ? (try assetProbe(descriptor.id, descriptor))
                : .swiftOnly
            let outcome = MigrationDecisionMatrix.decide(
                feature: descriptor.id,
                requiresAsset: descriptor.requiresAsset,
                assetPresence: presence,
                priorUsage: usage[descriptor.id] ?? .none
            )
            try await manager.setState(outcome.resultingState, for: descriptor.id)
            outcomes[descriptor.id] = outcome
        }

        // Drop the Sparkle marker (best-effort)
        let marker = featuresBaseDir.appendingPathComponent(".sparkle-migration-pending")
        try? FileManager.default.removeItem(at: marker)

        MigrationSentinel.markMigrated(defaults: defaults)

        // Skip onboarding for upgraders only after migration is durably marked.
        OnboardingState.completed.save()
        return MigrationReport(didRun: true, outcomes: outcomes)
    }

    // MARK: On-disk asset probing

    static func loadBundledManifest() -> FeaturePackManifest? {
        guard let url = Bundle.main.url(forResource: "FeaturePackManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? FeaturePackManifest.decode(from: data, expectedSchemaVersion: 1)
    }

    static func probeOnDisk(
        featureID: FeatureID,
        descriptor: FeatureDescriptor,
        featuresBaseDir: URL,
        manifest: FeaturePackManifest?
    ) throws -> MigrationDecisionMatrix.AssetPresence {
        guard let pack = descriptor.assetPacks.first,
              let manifest,
              let manifestEntry = manifest.packs[pack.bundledManifestKey]
        else { return .absent }

        let versionDir = featuresBaseDir
            .appendingPathComponent(featureID.rawValue, isDirectory: true)
            .appendingPathComponent(manifestEntry.version, isDirectory: true)

        let fm = FileManager.default
        guard fm.fileExists(atPath: versionDir.path) else { return .absent }

        for (filename, expected) in manifestEntry.files {
            let fileURL = versionDir.appendingPathComponent(filename)
            guard fm.fileExists(atPath: fileURL.path) else {
                return .shaMismatch(reason: "missing \(filename)")
            }
            let actual = try sha256Hex(of: fileURL)
            if actual.lowercased() != expected.sha256.lowercased() {
                return .shaMismatch(reason: "\(filename) SHA differs from manifest")
            }
        }
        return .presentMatchingSHA(version: manifestEntry.version)
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let bufSize = 65536
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: bufSize)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: Production factory

extension Migrator {
    /// Constructs a Migrator wired to the live ClipboardStore + DownloadStore.
    /// Used by `AppController.bootstrap`.
    static func makeProduction(
        clipboardStore: ClipboardStore,
        downloadStore: DownloadStore,
        defaults: UserDefaults = AppGroupSettings.defaults
    ) -> Migrator {
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: {
                // Use limit:1 so we get O(1) probe — we only need "≥ 1?"
                try clipboardStore.list(limit: 1).count
            },
            downloadRecordCount: {
                try downloadStore.list().count
            },
            folderPreviewLastInvoked: {
                defaults.object(forKey: PriorUsageDetector.folderPreviewLastInvokedKey) as? Date
            }
        )
        return Migrator(defaults: defaults, detector: detector)
    }
}

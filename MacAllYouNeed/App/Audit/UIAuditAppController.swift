#if DEBUG
import AppKit
import Core
import SwiftUI

@MainActor
final class UIAuditAppController {
    let configuration: UIAuditRuntimeConfiguration
    let manifest: UIAuditManifest
    let artifactDirectory: URL
    private var window: NSWindow?

    init(configuration: UIAuditRuntimeConfiguration) throws {
        self.configuration = configuration

        AppGroup.containerURLOverride = configuration.appGroupContainerURL
        guard let defaults = UserDefaults(suiteName: configuration.defaultsSuiteName) else {
            throw UIAuditAppControllerError.defaultsUnavailable(configuration.defaultsSuiteName)
        }
        defaults.removePersistentDomain(forName: configuration.defaultsSuiteName)
        Self.seed(defaults: defaults)
        AppGroupSettings.overrideDefaultsForCurrentProcess(defaults)

        let runID = configuration.appGroupContainerURL.lastPathComponent
        let pendingManifest = UIAuditManifest.make(
            runID: runID,
            gitSha: ProcessInfo.processInfo.environment["MAYN_UI_AUDIT_GIT_SHA"] ?? "unknown",
            buildConfiguration: "Debug",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            dataProfileID: "phase-one-demo",
            colorScheme: "system",
            windowSize: CGSize(width: 980, height: 680),
            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            scenarios: UIAuditSurfaceCatalog.phaseOneScenarios
        )
        let directory = try UIAuditArtifactWriter.write(
            manifest: pendingManifest,
            rootDirectory: configuration.appGroupContainerURL
        )
        // Persist a manifest immediately so a later screenshot/render failure still leaves
        // a machine-readable record of which scenarios were scheduled.
        _ = try? UIAuditArtifactWriter.write(
            manifest: pendingManifest.replacingScenarios(
                pendingManifest.scenarios.map { $0.withCaptureStatus(.pending) }
            ),
            rootDirectory: configuration.appGroupContainerURL
        )
        let capturedIDs = UIAuditScreenshotRenderer.writeScreenshots(for: pendingManifest, to: directory)
        manifest = pendingManifest.replacingScenarios(
            pendingManifest.scenarios.map { scenario in
                capturedIDs.contains(scenario.id)
                    ? scenario.withCaptureStatus(.captured)
                    : scenario.withCaptureStatus(.skipped, notCapturedReason: "Offscreen screenshot render failed.")
            }
        )
        artifactDirectory = try UIAuditArtifactWriter.write(
            manifest: manifest,
            rootDirectory: configuration.appGroupContainerURL
        )
    }

    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> UIAuditAppController {
        let configuration = try UIAuditLaunchMode.runtimeConfiguration(environment: environment)
        return try UIAuditAppController(configuration: configuration)
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac All You Need UI Audit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: UIAuditGalleryView(
                manifest: manifest,
                artifactDirectory: artifactDirectory
            )
        )
        return window
    }

    private static func seed(defaults: UserDefaults) {
        defaults.set(MainAppDestination.dashboard.rawValue, forKey: MainAppDestination.storageKey)
        defaults.set(ClipboardFunctionTab.history.rawValue, forKey: ClipboardFunctionTab.storageKey)
        defaults.set(VoiceFunctionTab.history.rawValue, forKey: VoiceFunctionTab.storageKey)
        defaults.set(DownloadsFunctionTab.downloads.rawValue, forKey: DownloadsFunctionTab.storageKey)
        defaults.set(SnippetsFunctionTab.library.rawValue, forKey: SnippetsFunctionTab.storageKey)
        defaults.set(SettingsDestination.general.rawValue, forKey: DockSettingsNavigation.settingsSelectionKey)
        defaults.set(3, forKey: "downloadConcurrency")
        defaults.set("%(title)s [%(id)s].%(ext)s", forKey: "downloadOutputTemplate")
        defaults.set(50_000, forKey: "folderPreviewMaxEntries")
        defaults.set(false, forKey: "folderPreviewIncludeHidden")
        defaults.set(true, forKey: FolderPreviewSettings.cascadeKey)
        defaults.set(SnippetExpansionSettings.defaultMode.rawValue, forKey: SnippetExpansionSettings.modeKey)
    }
}

private enum UIAuditAppControllerError: LocalizedError {
    case defaultsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .defaultsUnavailable(suiteName):
            "Could not create UI audit defaults suite \(suiteName)."
        }
    }
}
#endif

#if DEBUG
import Core
import CoreGraphics
import Foundation

enum UIAuditLiveServicePolicy: String, Codable, Equatable {
    case disabled
}

struct UIAuditRuntimeConfiguration: Equatable {
    let appGroupContainerURL: URL
    let defaultsSuiteName: String
    let liveServicePolicy: UIAuditLiveServicePolicy
}

enum UIAuditLaunchMode {
    static let environmentKey = "MAYN_UI_AUDIT"

    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let rawValue = environment[environmentKey] else { return false }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    static func runtimeConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> UIAuditRuntimeConfiguration {
        let runID = UIAuditRunID.make(date: Date())
        let containerURL = environment[AppGroup.containerOverrideEnvironmentKey]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("MacAllYouNeed-UIAudit", isDirectory: true)
                .appendingPathComponent(runID, isDirectory: true)
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let defaultsSuiteName = environment[AppGroupSettings.defaultsSuiteOverrideEnvironmentKey]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "com.macallyouneed.ui-audit.\(runID)"

        return UIAuditRuntimeConfiguration(
            appGroupContainerURL: containerURL,
            defaultsSuiteName: defaultsSuiteName,
            liveServicePolicy: .disabled
        )
    }
}

enum UIAuditRunID {
    static func make(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

enum UIAuditNativeRenderingMode: String, CaseIterable, Codable, Equatable {
    case nativeIsolated = "native-isolated"
    case simulatedEquivalent = "simulated-equivalent"
    case manualOnly = "manual-only"
}

enum UIAuditSensitivityRisk: String, CaseIterable, Codable, Equatable {
    case low
    case medium
    case high
}

enum UIAuditCaptureStatus: String, Codable, Equatable {
    case pending
    case captured
    case skipped
}

struct UIAuditScenario: Identifiable, Codable, Equatable {
    let id: String
    let surface: String
    let route: String
    let state: String
    let nativeRenderingMode: UIAuditNativeRenderingMode
    let sensitivityRisk: UIAuditSensitivityRisk
    let expectedRedactions: [String]
    let screenshotFilename: String
    let captureStatus: UIAuditCaptureStatus
    let notCapturedReason: String?
    let stabilityWaitHintMilliseconds: Int

    init(
        id: String,
        surface: String,
        route: String,
        state: String,
        nativeRenderingMode: UIAuditNativeRenderingMode,
        sensitivityRisk: UIAuditSensitivityRisk = .low,
        expectedRedactions: [String] = [],
        captureStatus: UIAuditCaptureStatus = .pending,
        notCapturedReason: String? = nil,
        stabilityWaitHintMilliseconds: Int = 250
    ) {
        self.id = id
        self.surface = surface
        self.route = route
        self.state = state
        self.nativeRenderingMode = nativeRenderingMode
        self.sensitivityRisk = sensitivityRisk
        self.expectedRedactions = expectedRedactions
        self.screenshotFilename = "\(id).png"
        self.captureStatus = captureStatus
        self.notCapturedReason = notCapturedReason
        self.stabilityWaitHintMilliseconds = stabilityWaitHintMilliseconds
    }

    func withCaptureStatus(
        _ captureStatus: UIAuditCaptureStatus,
        notCapturedReason: String? = nil
    ) -> UIAuditScenario {
        UIAuditScenario(
            id: id,
            surface: surface,
            route: route,
            state: state,
            nativeRenderingMode: nativeRenderingMode,
            sensitivityRisk: sensitivityRisk,
            expectedRedactions: expectedRedactions,
            captureStatus: captureStatus,
            notCapturedReason: notCapturedReason,
            stabilityWaitHintMilliseconds: stabilityWaitHintMilliseconds
        )
    }
}

enum UIAuditSurfaceCatalog {
    static let requiredPhaseOneScenarioIDs: Set<String> = [
        "dashboard.overview.enabled",
        "main.clipboard.history",
        "main.voice.history",
        "main.downloads.queue.running",
        "command-center.clipboard",
        "dock.clipboard.history",
        "voice-hud.listening",
        "dialog.reset.view-only"
    ]

    static let phaseOneScenarios: [UIAuditScenario] = [
        UIAuditScenario(
            id: "dashboard.overview.enabled",
            surface: "Main Window",
            route: "Dashboard",
            state: "Feature cards enabled",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.clipboard.history",
            surface: "Main Window",
            route: "Clipboard / History",
            state: "Mixed demo clipboard items",
            nativeRenderingMode: .simulatedEquivalent,
            sensitivityRisk: .medium,
            expectedRedactions: ["clipboard body text is synthetic"]
        ),
        UIAuditScenario(
            id: "main.voice.history",
            surface: "Main Window",
            route: "Voice / History",
            state: "Transcript list",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.voice.models",
            surface: "Main Window",
            route: "Voice / Models",
            state: "Local model installed, cloud optional",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.downloads.empty",
            surface: "Main Window",
            route: "Downloads / Queue",
            state: "Empty queue",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.downloads.queue.running",
            surface: "Main Window",
            route: "Downloads / Queue",
            state: "Running download",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.downloads.queue.failed",
            surface: "Main Window",
            route: "Downloads / Queue",
            state: "Failed row and retry banner",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.downloads.completed",
            surface: "Main Window",
            route: "Downloads / Completed",
            state: "Completed downloads",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "main.snippets.library",
            surface: "Main Window",
            route: "Snippets / Library",
            state: "Snippet list with selection",
            nativeRenderingMode: .simulatedEquivalent,
            sensitivityRisk: .medium,
            expectedRedactions: ["snippet body text is synthetic"]
        ),
        UIAuditScenario(
            id: "main.folder-preview.settings",
            surface: "Main Window",
            route: "Enhanced Finder / Settings",
            state: "Preview settings",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "command-center.clipboard",
            surface: "Command Center",
            route: "Clipboard tab",
            state: "Recent clipboard items",
            nativeRenderingMode: .nativeIsolated,
            sensitivityRisk: .medium,
            expectedRedactions: ["clipboard body text is synthetic"]
        ),
        UIAuditScenario(
            id: "command-center.downloads",
            surface: "Command Center",
            route: "Downloads tab",
            state: "Compact running and failed rows",
            nativeRenderingMode: .nativeIsolated
        ),
        UIAuditScenario(
            id: "dock.clipboard.history",
            surface: "Clipboard Dock",
            route: "History tab",
            state: "Card grid with selected item",
            nativeRenderingMode: .nativeIsolated,
            sensitivityRisk: .medium,
            expectedRedactions: ["clipboard body text is synthetic"]
        ),
        UIAuditScenario(
            id: "dock.snippets.create",
            surface: "Clipboard Dock",
            route: "Snippets tab / Create",
            state: "Create snippet overlay",
            nativeRenderingMode: .nativeIsolated,
            sensitivityRisk: .medium,
            expectedRedactions: ["snippet body text is synthetic"]
        ),
        UIAuditScenario(
            id: "voice-hud.listening",
            surface: "Voice HUD",
            route: "Mini HUD",
            state: "Listening",
            nativeRenderingMode: .nativeIsolated,
            stabilityWaitHintMilliseconds: 500
        ),
        UIAuditScenario(
            id: "voice-hud.cancelled-undo",
            surface: "Voice HUD",
            route: "Mini HUD",
            state: "Cancelled with Undo",
            nativeRenderingMode: .nativeIsolated,
            stabilityWaitHintMilliseconds: 500
        ),
        UIAuditScenario(
            id: "onboarding.permission.accessibility",
            surface: "Onboarding",
            route: "Permissions",
            state: "Accessibility denied with repair instructions",
            nativeRenderingMode: .simulatedEquivalent
        ),
        UIAuditScenario(
            id: "dialog.reset.view-only",
            surface: "Destructive Dialog",
            route: "Advanced / Reset",
            state: "View-only reset confirmation",
            nativeRenderingMode: .simulatedEquivalent,
            sensitivityRisk: .high,
            expectedRedactions: ["destructive action disabled in audit mode"]
        )
    ]
}

struct UIAuditManifest: Codable, Equatable {
    let runID: String
    let gitSha: String
    let buildConfiguration: String
    let appVersion: String
    let dataProfileID: String
    let colorScheme: String
    let windowSize: CGSize
    let reducedMotion: Bool
    let scenarios: [UIAuditScenario]

    static func make(
        runID: String,
        gitSha: String,
        buildConfiguration: String,
        appVersion: String,
        dataProfileID: String,
        colorScheme: String,
        windowSize: CGSize,
        reducedMotion: Bool,
        scenarios: [UIAuditScenario]
    ) -> UIAuditManifest {
        UIAuditManifest(
            runID: runID,
            gitSha: gitSha,
            buildConfiguration: buildConfiguration,
            appVersion: appVersion,
            dataProfileID: dataProfileID,
            colorScheme: colorScheme,
            windowSize: windowSize,
            reducedMotion: reducedMotion,
            scenarios: scenarios
        )
    }

    func replacingScenarios(_ scenarios: [UIAuditScenario]) -> UIAuditManifest {
        UIAuditManifest(
            runID: runID,
            gitSha: gitSha,
            buildConfiguration: buildConfiguration,
            appVersion: appVersion,
            dataProfileID: dataProfileID,
            colorScheme: colorScheme,
            windowSize: windowSize,
            reducedMotion: reducedMotion,
            scenarios: scenarios
        )
    }
}
#endif

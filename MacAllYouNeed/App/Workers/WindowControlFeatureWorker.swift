import FeatureCore
import Foundation

/// Heavy diagnostics / AX snapshots only — event taps stay on the main run loop.
actor WindowControlFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    /// Runs heavy AX snapshot / export work off the main actor (settings diagnostics only).
    func runDiagnostics<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard isRunning else { return try await operation() }
        return try await operation()
    }

    func formatDiagnosticsReport(_ snapshot: WindowControlDiagnosticsSnapshot) async -> String {
        guard isRunning else { return Self.formatReport(snapshot) }
        return Self.formatReport(snapshot)
    }

    private static func formatReport(_ snapshot: WindowControlDiagnosticsSnapshot) -> String {
        var lines: [String] = []
        lines.append("Mac All You Need — Window Control")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("Event tap: \(snapshot.eventTapStatus)")
        lines.append(snapshot.eventTapDetail)
        lines.append("")
        lines.append("Last action: \(snapshot.lastAction)")
        lines.append(snapshot.lastResultDetail)
        lines.append("")
        lines.append("Accessibility trusted: \(snapshot.accessibilityTrusted)")
        if let bundle = snapshot.frontmostBundleID {
            lines.append("Frontmost app: \(bundle)")
        }
        return lines.joined(separator: "\n")
    }
}

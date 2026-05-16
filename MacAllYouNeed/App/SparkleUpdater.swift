import Foundation

/// Wrapper for the Sparkle pre-install migration script.
///
/// Sparkle 2 itself is a Plan 7 / Phase 12 dependency (pending paid Developer ID cert).
/// The `#if canImport(Sparkle)` guards make this a no-op until that package is wired in.
/// The `runPreInstallScript` method is functional today — tested by `PreInstallScriptTests`.
final class SparkleUpdater: NSObject {
    static let shared = SparkleUpdater()

    private override init() { super.init() }

    /// Runs `Resources/Migration/pre-install.sh` inside the current app bundle.
    /// Called by the Sparkle delegate after a new update is downloaded and verified
    /// but before Sparkle swaps the bundles.
    ///
    /// - Parameters:
    ///   - oldAppPath: Path to the currently-installed (old) app bundle.
    ///   - newVersion: Marketing version string of the incoming new bundle.
    /// - Returns: The script's exit code, or `-1` if the script couldn't be launched.
    @discardableResult
    func runPreInstallScript(oldAppPath: String, newVersion: String) -> Int32 {
        guard let scriptURL = Bundle.main.url(
            forResource: "pre-install",
            withExtension: "sh",
            subdirectory: "Migration"
        ) else {
            NSLog("[SparkleUpdater] pre-install.sh not found in bundle; skipping")
            return -1
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, oldAppPath, newVersion]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            NSLog("[SparkleUpdater] pre-install script failed to launch: \(error)")
            return -1
        }
    }
}

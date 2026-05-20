#if DEBUG
import Foundation

enum UIAuditArtifactWriter {
    static func write(manifest: UIAuditManifest, rootDirectory: URL) throws -> URL {
        let directory = rootDirectory
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("ui-audit", isDirectory: true)
            .appendingPathComponent(manifest.runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        try indexMarkdown(for: manifest).write(
            to: directory.appendingPathComponent("index.md"),
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    private static func indexMarkdown(for manifest: UIAuditManifest) -> String {
        var lines: [String] = [
            "# Mac All You Need UI Audit",
            "",
            "- Run ID: `\(manifest.runID)`",
            "- Git SHA: `\(manifest.gitSha)`",
            "- Build: `\(manifest.buildConfiguration)`",
            "- Data profile: `\(manifest.dataProfileID)`",
            "- Color scheme: `\(manifest.colorScheme)`",
            "- Window: `\(Int(manifest.windowSize.width))x\(Int(manifest.windowSize.height))`",
            "- Reduced motion: `\(manifest.reducedMotion)`",
            "",
            "| Scenario | Surface | State | Mode | Status | Screenshot |",
            "|---|---|---|---|---|---|"
        ]

        lines.append(contentsOf: manifest.scenarios.map { scenario in
            "| `\(scenario.id)` | \(scenario.surface) | \(scenario.state) | \(scenario.nativeRenderingMode.rawValue) | \(scenario.captureStatus.rawValue) | `\(scenario.screenshotFilename)` |"
        })
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
#endif

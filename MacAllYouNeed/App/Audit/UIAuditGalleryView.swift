#if DEBUG
import AppKit
import SwiftUI

struct UIAuditGalleryView: View {
    let manifest: UIAuditManifest
    let artifactDirectory: URL
    @State private var selectedID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(manifest: UIAuditManifest, artifactDirectory: URL) {
        self.manifest = manifest
        self.artifactDirectory = artifactDirectory
        self._selectedID = State(initialValue: manifest.scenarios.first?.id ?? "")
    }

    private var selectedScenario: UIAuditScenario? {
        manifest.scenarios.first { $0.id == selectedID } ?? manifest.scenarios.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 310)
                .background(MAYNTheme.panel)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MAYNTheme.window)
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("UI Audit Gallery")
                    .font(.title3.weight(.semibold))
                Text("Phase 1 demo scenarios")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Text("Manifest: \(artifactDirectory.path)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(manifest.scenarios) { scenario in
                        UIAuditScenarioButton(
                            scenario: scenario,
                            isSelected: selectedID == scenario.id
                        ) {
                            selectedID = scenario.id
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let scenario = selectedScenario {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    UIAuditScenarioHeader(scenario: scenario)
                    UIAuditScenarioPreview(scenario: scenario)
                    UIAuditScenarioMetadata(scenario: scenario, manifest: manifest)
                }
                .padding(24)
                .frame(maxWidth: 920, alignment: .leading)
            }
            .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: selectedID)
        } else {
            ContentUnavailableView("No audit scenarios", systemImage: "rectangle.on.rectangle.slash")
        }
    }
}

private struct UIAuditScenarioButton: View {
    let scenario: UIAuditScenario
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(scenario.surface)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    StatusPill(text: scenario.captureStatus.rawValue.capitalized, kind: .neutral)
                }

                Text(scenario.state)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(scenario.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .stroke(isSelected ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return MAYNTheme.selected }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private struct UIAuditScenarioHeader: View {
    let scenario: UIAuditScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(scenario.surface)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(scenario.state)
                        .font(.title2.weight(.semibold))
                }
                Spacer(minLength: 12)
                StatusPill(text: scenario.nativeRenderingMode.rawValue, kind: modeKind)
            }

            HStack(spacing: 10) {
                Label(scenario.route, systemImage: "arrow.triangle.branch")
                Label(scenario.screenshotFilename, systemImage: "camera")
                Label("\(scenario.stabilityWaitHintMilliseconds)ms", systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var modeKind: StatusPill.Kind {
        switch scenario.nativeRenderingMode {
        case .nativeIsolated: .progress
        case .simulatedEquivalent: .neutral
        case .manualOnly: .warning
        }
    }
}

private struct UIAuditScenarioPreview: View {
    let scenario: UIAuditScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(.headline)
            previewContent
                .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
                .padding(18)
                .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if scenario.id.contains("downloads") {
            UIAuditDownloadsPreview(state: scenario.state)
        } else if scenario.id.contains("voice-hud") {
            UIAuditVoiceHUDPreview(state: scenario.state)
        } else if scenario.id.contains("command-center") {
            UIAuditCompactListPreview(title: "Command Center", rows: ["Clipboard: Project brief", "Downloads: Demo video", "Voice: Cleanup ready"])
        } else if scenario.id.contains("dock") {
            UIAuditCompactListPreview(title: "Clipboard Dock", rows: ["Design notes", ";email snippet", "Palette #4A90E2"])
        } else if scenario.id.contains("dialog") {
            UIAuditDialogPreview()
        } else if scenario.id.contains("onboarding") {
            UIAuditPermissionPreview()
        } else {
            UIAuditMainPagePreview(scenario: scenario)
        }
    }
}

private struct UIAuditMainPagePreview: View {
    let scenario: UIAuditScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(scenario.route)
                    .font(.title3.weight(.semibold))
                Spacer()
                StatusPill(text: "Demo Data", kind: .success)
            }
            HStack(spacing: 12) {
                ForEach(["Primary state", "Empty state", "Error state"], id: \.self) { title in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.callout.weight(.medium))
                        Text("Sanitized content for screenshot review.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                }
            }
            UIAuditCompactListPreview(title: "Rows", rows: ["Synthetic text item", "Code block sample", "Folder preview sample"])
        }
    }
}

private struct UIAuditDownloadsPreview: View {
    let state: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Downloads")
                    .font(.title3.weight(.semibold))
                Spacer()
                StatusPill(text: state, kind: state.contains("Failed") ? .danger : .progress)
            }
            ForEach(["Demo Video.mp4", "Conference Talk.webm", "Music Clip.m4a"], id: \.self) { row in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row)
                            .font(.callout.weight(.medium))
                        Text("https://example.invalid/video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: row.contains("Conference") ? "Failed" : "Running", kind: row.contains("Conference") ? .danger : .progress)
                }
                .padding(12)
                .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius))
            }
        }
    }
}

private struct UIAuditVoiceHUDPreview: View {
    let state: String

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Image(systemName: state.contains("Cancelled") ? "arrow.uturn.backward" : "waveform")
                Text(state)
                    .font(.callout.weight(.semibold))
                Image(systemName: state.contains("Cancelled") ? "return" : "xmark")
                    .font(.caption)
            }
            .frame(width: 144, height: 32)
            .background(MAYNTheme.panel, in: Capsule())
            .overlay(Capsule().stroke(MAYNTheme.strongBorder, lineWidth: 1))
            Text("Fixed 144x32 HUD preview with synthetic state.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UIAuditCompactListPreview: View {
    let title: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.self) { row in
                HStack {
                    Text(row)
                        .font(.callout)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(MAYNTheme.divider)
                        .frame(height: 1)
                }
            }
        }
    }
}

private struct UIAuditPermissionPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accessibility Permission")
                .font(.title3.weight(.semibold))
            Text("Demo denied state with repair instructions. No live permission prompt is opened.")
                .foregroundStyle(.secondary)
            StatusPill(text: "Denied", kind: .warning)
        }
    }
}

private struct UIAuditDialogPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reset Mac All You Need?")
                .font(.title3.weight(.semibold))
            Text("View-only destructive confirmation. Confirm actions are disabled in audit mode.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") {}
                    .disabled(true)
                Button("Reset") {}
                    .disabled(true)
            }
        }
    }
}

private struct UIAuditScenarioMetadata: View {
    let scenario: UIAuditScenario
    let manifest: UIAuditManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture Metadata")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                metadataRow("Scenario", scenario.id)
                metadataRow("Run", manifest.runID)
                metadataRow("Git", manifest.gitSha)
                metadataRow("Mode", scenario.nativeRenderingMode.rawValue)
                metadataRow("Risk", scenario.sensitivityRisk.rawValue)
                metadataRow("Redactions", scenario.expectedRedactions.isEmpty ? "None" : scenario.expectedRedactions.joined(separator: ", "))
            }
            .font(.caption)
        }
        .padding(14)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius))
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

@MainActor
enum UIAuditScreenshotRenderer {
    static func writeScreenshots(for manifest: UIAuditManifest, to directory: URL) -> Set<String> {
        var capturedIDs = Set<String>()

        for scenario in manifest.scenarios where scenario.captureStatus != .skipped {
            autoreleasepool {
                let view = UIAuditScenarioCaptureView(scenario: scenario, manifest: manifest)
                    .frame(width: manifest.windowSize.width, height: manifest.windowSize.height)
                    .background(MAYNTheme.window)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2

                guard let image = renderer.nsImage,
                      let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:])
                else {
                    return
                }

                do {
                    try pngData.write(to: directory.appendingPathComponent(scenario.screenshotFilename))
                    capturedIDs.insert(scenario.id)
                } catch {
                    return
                }
            }
        }

        return capturedIDs
    }
}

private struct UIAuditScenarioCaptureView: View {
    let scenario: UIAuditScenario
    let manifest: UIAuditManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UIAuditScenarioHeader(scenario: scenario)
            UIAuditScenarioPreview(scenario: scenario)
            UIAuditScenarioMetadata(scenario: scenario, manifest: manifest)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif

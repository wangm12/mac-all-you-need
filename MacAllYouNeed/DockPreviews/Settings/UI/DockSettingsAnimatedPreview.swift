import AppKit
import SwiftUI

/// Looping settings preview (GIF-style) with uniform padding, corner radius, and context-specific motion.
struct DockSettingsAnimatedPreview: View {
    let snapshot: DockSettingsPreviewSnapshot
    let context: DockSettingsMockPreviewContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let previewRadius = MAYNControlMetrics.cardRadius
    private let cardWidth: CGFloat = 96
    private let cardHeight: CGFloat = 60

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 10) {
                contextPreview(phase: phase)
                indicatorCaption
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 168)
    }

    private var indicatorCaption: some View {
        Text(context.indicatorCaption)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func contextPreview(phase: TimeInterval) -> some View {
        switch context {
        case .dock:
            dockHoverPreview(phase: phase)
        case .windowSwitcher:
            switcherPreview(phase: phase)
        case .cmdTab:
            cmdTabPreview(phase: phase)
        }
    }

    // MARK: - Dock hover

    private func dockHoverPreview(phase: TimeInterval) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 3.4)
        let showPanel = cycle > 0.75
        let hoverIcon = showPanel ? 1 : Int((cycle / 0.75).truncatingRemainder(dividingBy: 3.0))

        return VStack(spacing: 8) {
            previewPanel(
                selectedIndex: showPanel ? 0 : -1,
                emphasizeSelection: showPanel
            )
            .scaleEffect(showPanel ? 1 : 0.94, anchor: .bottom)
            .opacity(showPanel ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: showPanel)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(index == hoverIcon ? 0.24 : 0.11))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    // MARK: - Window switcher

    private func switcherPreview(phase: TimeInterval) -> some View {
        let selected = Int(phase.truncatingRemainder(dividingBy: 2.7) / 0.9) % snapshot.windows.count

        return previewPanel(selectedIndex: selected, emphasizeSelection: true)
    }

    // MARK: - Cmd+Tab

    private func cmdTabPreview(phase: TimeInterval) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 3.0)
        let commandHeld = cycle > 0.4
        let selected = commandHeld ? Int((cycle - 0.4) / 0.8) % snapshot.windows.count : -1
        let pulse = (sin(phase * 4.0) + 1) / 2

        return VStack(spacing: 8) {
            previewPanel(
                selectedIndex: selected,
                emphasizeSelection: commandHeld
            )
            .opacity(commandHeld ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: commandHeld)

            HStack(spacing: 4) {
                Image(systemName: "command")
                    .font(.caption.weight(.semibold))
                    .opacity(commandHeld ? 0.85 : 0.35 + pulse * 0.25)
                Text("held")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(commandHeld ? .primary : .secondary)
            }
        }
    }

    // MARK: - Shared panel

    @ViewBuilder
    private func previewPanel(selectedIndex: Int, emphasizeSelection: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.showAppHeader {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Preview.app"))
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text(snapshot.appName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 8) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { index, window in
                    mockWindowCard(
                        window: window,
                        isSelected: emphasizeSelection && index == selectedIndex
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .dockPreviewDockStyle(
            backgroundOpacity: snapshot.panelOpacity,
            appearance: snapshot.appearance.background,
            cornerRadius: previewRadius
        )
        .animation(reduceMotion ? nil : MAYNMotion.hoverAnimation(reduceMotion: false), value: selectedIndex)
    }

    @ViewBuilder
    private func mockWindowCard(window: DockSettingsMockWindow, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.appearance.showWindowTitle {
                Text(window.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: previewRadius, style: .continuous)
                .fill(thumbnailColor(for: window.tint))
                .frame(width: cardWidth, height: cardHeight)
                .overlay {
                    if !snapshot.appearance.showWindowTitle {
                        Text(window.thumbnailLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: previewRadius, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.5)
                    }
                }
                .opacity(isSelected ? 1 : snapshot.appearance.unselectedOpacity)
                .scaleEffect(isSelected ? 1.02 : 0.98)
        }
    }

    private func thumbnailColor(for tint: DockBackgroundStyleFull) -> Color {
        switch tint {
        case .liquidGlass: Color.teal.opacity(0.22)
        case .frostedMaterial: Color.indigo.opacity(0.16)
        case .clear: Color.primary.opacity(0.08)
        }
    }
}

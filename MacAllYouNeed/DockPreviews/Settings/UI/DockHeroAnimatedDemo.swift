import SwiftUI

/// Looping feature demo (GIF-style) for settings hero slots.
struct DockHeroAnimatedDemo: View {
    let art: DockHeroArt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 8) {
                demoContent(phase: phase)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(art.indicatorCaption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MAYNTheme.elevated, MAYNTheme.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MAYNTheme.divider, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func demoContent(phase: TimeInterval) -> some View {
        switch art {
        case .dockPreviews:
            dockPreviewDemo(phase: phase)
        case .windowSwitcher:
            switcherDemo(phase: phase)
        case .cmdTab:
            cmdTabDemo(phase: phase)
        case .dockLocking:
            dockLockDemo(phase: phase)
        case .activeIndicator:
            activeIndicatorDemo(phase: phase)
        }
    }

    private func dockPreviewDemo(phase: TimeInterval) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 3.0)
        let showPanel = cycle > 0.8
        let hoverIndex = showPanel ? 1 : Int((cycle / 0.8).truncatingRemainder(dividingBy: 3.0))

        return VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(showPanel ? 0.14 : 0.04))
                .frame(height: 30)
                .overlay(alignment: .topLeading) {
                    if showPanel {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.18))
                                .frame(width: 34, height: 20)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 34, height: 20)
                        }
                        .padding(5)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: showPanel)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(index == hoverIndex ? 0.28 : 0.12))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    private func switcherDemo(phase: TimeInterval) -> some View {
        let selected = Int(phase.truncatingRemainder(dividingBy: 2.4) / 0.8) % 3

        return HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(index == selected ? 0.24 : 0.1))
                    .frame(width: 36, height: 24)
                    .overlay {
                        if index == selected {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                        }
                    }
            }
        }
    }

    private func cmdTabDemo(phase: TimeInterval) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 2.5)
        let commandHeld = cycle > 0.35
        let pulse = (sin(phase * 3.5) + 1) / 2

        return VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(commandHeld ? 0.14 : 0.05))
                .frame(height: 28)
                .overlay {
                    if commandHeld {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.16))
                                .frame(width: 36, height: 18)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 36, height: 18)
                        }
                    }
                }

            Image(systemName: "command")
                .font(.system(size: 16, weight: .semibold))
                .opacity(commandHeld ? 0.9 : 0.35 + pulse * 0.35)
        }
    }

    private func dockLockDemo(phase: TimeInterval) -> some View {
        let shift = (sin(phase * 2.0) + 1) / 2

        return HStack(spacing: 10) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 34, height: 20)
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .offset(x: CGFloat(shift) * 6)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 34, height: 20)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 24, height: 3)
                        .padding(.bottom, 2)
                }
        }
    }

    private func activeIndicatorDemo(phase: TimeInterval) -> some View {
        let pulse = (sin(phase * 4.0) + 1) / 2

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(index == 1 ? 0.2 : 0.1))
                        .frame(width: 22, height: 22)
                }
            }
            Capsule()
                .fill(Color.accentColor.opacity(0.55 + pulse * 0.45))
                .frame(width: 28, height: 4)
        }
    }
}

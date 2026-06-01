import Core
import SwiftUI

/// Non-interactive radial menu preview shown in Settings (segment cycling only).
struct RadialSettingsPreview: View {
    @State private var selectedIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scaled-down live menu; all layout derives from this radius via `RadialMenuMetrics`.
    private static let previewMenuRadius = RadialMenuMetrics.menuRadius * 0.8
    private let previewActions: [Int] = [0, 2, 4]

    var body: some View {
        RadialMenuView(
            actions: RadialMenuLayout.ringActions,
            selectedIndex: selectedIndex,
            showsClosePill: false,
            menuRadius: Self.previewMenuRadius
        )
        .frame(
            width: RadialMenuMetrics.panelSize(for: Self.previewMenuRadius, showsClosePill: false).width,
            height: RadialMenuMetrics.panelSize(for: Self.previewMenuRadius, showsClosePill: false).height
        )
        .allowsHitTesting(false)
        .onAppear(perform: startCycle)
        .onDisappear { cycleTask?.cancel() }
    }

    @State private var cycleTask: Task<Void, Never>?

    private func startCycle() {
        cycleTask?.cancel()
        guard !reduceMotion else {
            selectedIndex = previewActions[0]
            return
        }
        cycleTask = Task { @MainActor in
            var step = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                step = (step + 1) % previewActions.count
                withAnimation(MAYNMotion.animation(.control, reduceMotion: reduceMotion)) {
                    selectedIndex = previewActions[step]
                }
            }
        }
    }
}

import SwiftUI

/// First-run Cmd+Tab focus hints (DockDoor `CmdTabFocusFullOverlayView`).
struct DockCmdTabFocusOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme

    let cycleKeyLabel: String

    private var overlayColor: Color { colorScheme == .dark ? .black.opacity(0.4) : .white.opacity(0.4) }
    private var titleColor: Color { colorScheme == .dark ? .white : .black }
    private var textColor: Color { colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85) }

    var body: some View {
        ZStack {
            overlayColor
            VStack(spacing: 14) {
                Text("Focus and use previews")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(titleColor)
                HStack(spacing: 6) {
                    Text("⌘")
                    Text(cycleKeyLabel)
                    Text("Cycle through previews (Shift to reverse)")
                        .font(.subheadline)
                }
                .foregroundStyle(textColor)
                Divider().overlay(titleColor.opacity(0.25)).padding(.horizontal, 24)
                hintRow(symbol: "arrow.left.and.right", text: "Move between windows")
                hintRow(symbol: "arrow.down", text: "Clear focus")
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    private func hintRow(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(textColor)
    }
}

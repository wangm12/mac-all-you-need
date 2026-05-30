import Core
import SwiftUI

/// Non-interactive radial menu preview shown in Settings to illustrate the
/// gesture. Shows the "top" segment selected as an example.
struct RadialSettingsPreview: View {
    var body: some View {
        RadialMenuView(
            actions: RadialMenuLayout.ringActions,
            selectedIndex: 0,
            menuRadius: 80
        )
        .frame(width: 160, height: 160)
        .allowsHitTesting(false)
        .opacity(0.85)
        .overlay(
            Text("Preview")
                .font(.caption2)
                .foregroundStyle(MAYNTheme.muted),
            alignment: .bottom
        )
    }
}

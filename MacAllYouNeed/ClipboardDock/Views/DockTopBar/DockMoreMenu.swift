import SwiftUI

struct DockMoreMenu: View {
    let openSettings: () -> Void

    var body: some View {
        Menu {
            Button("Open Settings…") {
                openSettings()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
    }
}

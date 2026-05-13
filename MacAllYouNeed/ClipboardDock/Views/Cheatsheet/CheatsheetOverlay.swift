import SwiftUI

struct CheatsheetOverlay: View {
    let registry: ShortcutRegistry

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.fixed(160))]

        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .bold()

                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(ShortcutAction.allCases) { action in
                        Text(action.label)
                            .font(.callout)

                        Text(registry.bindings(for: action).map { $0.display() }.joined(separator: " · "))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .frame(maxWidth: 600)
        }
        .transition(.opacity)
    }
}

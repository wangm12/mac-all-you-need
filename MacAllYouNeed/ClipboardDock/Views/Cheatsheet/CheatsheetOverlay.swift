import SwiftUI

struct CheatsheetOverlay: View {
    let registry: ShortcutRegistry

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.fixed(190))]

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

                        HStack(spacing: 6) {
                            ForEach(registry.bindings(for: action), id: \.self) { binding in
                                ShortcutChip(text: binding.display(), height: HotkeyChipPresentation.compactHeight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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

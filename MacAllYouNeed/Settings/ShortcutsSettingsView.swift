import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var registry: ShortcutRegistry
    @State private var pendingError: String?

    var body: some View {
        MAYNSettingsPage(
            title: "Shortcuts",
            subtitle: "Customize keyboard shortcuts used inside the clipboard dock."
        ) {
            MAYNSection(title: "In-dock shortcuts") {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element.id) { offset, action in
                    MAYNSettingsRow(
                        title: action.label,
                        subtitle: "Capture a key combination or reset to the default binding.",
                        minHeight: 58
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 6) {
                                ForEach(registry.bindings(for: action), id: \.self) { binding in
                                    ShortcutChip(text: binding.display())
                                        .contextMenu {
                                            Button("Remove") {
                                                registry.removeBinding(binding, for: action)
                                            }
                                        }
                                }
                            }

                            HStack(spacing: 8) {
                                ShortcutRecorderView(binding: .constant(nil)) { captured in
                                    do {
                                        try registry.validate(captured, for: action)
                                        registry.addBinding(captured, for: action)
                                        pendingError = nil
                                    } catch {
                                        pendingError = "Cannot bind reserved key."
                                    }
                                }
                                .frame(width: 130, height: 22)

                                Button("Reset") {
                                    registry.reset(action: action)
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    if offset != ShortcutAction.allCases.count - 1 {
                        MAYNDivider()
                    }
                }
            }

            if let pendingError {
                MAYNSection(title: "Status") {
                    MAYNSettingsRow(title: "Shortcut error") {
                        StatusPill(text: pendingError, kind: .danger)
                    }
                }
            }
        }
    }
}

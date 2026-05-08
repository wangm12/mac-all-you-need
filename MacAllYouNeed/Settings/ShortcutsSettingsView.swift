import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var registry: ShortcutRegistry
    @State private var pendingError: String?

    var body: some View {
        Form {
            Section("In-Dock Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.label)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(registry.bindings(for: action), id: \.self) { binding in
                            Text(binding.display())
                                .font(.system(.callout, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                                .contextMenu {
                                    Button("Remove") {
                                        registry.removeBinding(binding, for: action)
                                    }
                                }
                        }

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

            if let pendingError {
                Text(pendingError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .padding()
    }
}

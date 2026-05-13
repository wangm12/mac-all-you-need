import Platform
import SwiftUI

struct HotkeysSettingsView: View {
    let controller: AppController
    @State private var map: [HotkeyAction: [HotkeyDescriptor]]
    @State private var errorMessage: String?

    init(controller: AppController) {
        self.controller = controller
        _map = State(initialValue: HotkeyMapStore.load())
    }

    var body: some View {
        MAYNSettingsPage(
            title: "Hotkeys",
            subtitle: "Set global keyboard triggers for app-wide commands."
        ) {
            MAYNSection(title: "Global triggers") {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element.id) { offset, action in
                    let descriptors = map[action] ?? [action.defaultDescriptor]
                    MAYNSettingsRow(
                        title: action.label,
                        subtitle: "Add up to three trigger combinations.",
                        minHeight: descriptors.count > 1 ? 46 + CGFloat(descriptors.count - 1) * 32 : 46
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) {
                                HotkeyRecorder(descriptor: binding(for: action, index: 0, defaultValue: action.defaultDescriptor))
                                    .frame(width: 100, height: 24)
                                Button {
                                    var updated = descriptors
                                    guard updated.count < 3 else { return }
                                    updated.append(action.defaultDescriptor)
                                    map[action] = updated
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Add another trigger")
                            }

                            ForEach(Array(descriptors.dropFirst().enumerated()), id: \.offset) { offset, _ in
                                let index = offset + 1
                                HStack(spacing: 8) {
                                    HotkeyRecorder(descriptor: binding(for: action, index: index, defaultValue: action.defaultDescriptor))
                                        .frame(width: 100, height: 24)
                                    Button {
                                        var updated = descriptors
                                        updated.remove(at: index)
                                        map[action] = updated
                                    } label: {
                                        Image(systemName: "delete.left")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove trigger")
                                }
                            }
                        }
                    }

                    if offset != HotkeyAction.allCases.count - 1 {
                        MAYNDivider()
                    }
                }
            }

            MAYNSection(title: "Changes") {
                MAYNSettingsRow(
                    title: "Apply hotkeys",
                    subtitle: "Validate conflicts, save the map, and register the new shortcuts."
                ) {
                    Button("Apply") { apply() }
                }

                if let errorMessage {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Validation error") {
                        StatusPill(text: errorMessage, kind: .danger)
                    }
                }
            }
        }
    }

    private func binding(for action: HotkeyAction, index: Int, defaultValue: HotkeyDescriptor) -> Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let descriptors = map[action] ?? [defaultValue]
                if descriptors.indices.contains(index) {
                    return descriptors[index]
                }
                return defaultValue
            },
            set: { newValue in
                var descriptors = map[action] ?? [defaultValue]
                while descriptors.count <= index {
                    descriptors.append(defaultValue)
                }
                descriptors[index] = newValue
                map[action] = descriptors
            }
        )
    }

    private func apply() {
        do {
            try controller.applyHotkeyMap(map)
            HotkeyMapStore.save(map)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

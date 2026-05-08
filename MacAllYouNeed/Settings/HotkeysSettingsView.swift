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
        Form {
            ForEach(HotkeyAction.allCases) { action in
                let descriptors = map[action] ?? [action.defaultDescriptor]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(action.label)
                        Spacer()
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
                        HStack {
                            Spacer()
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

            HStack {
                Spacer()
                Button("Apply") { apply() }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
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
            let registry = HotkeyRegistry()
            try registry.apply(map, controller: controller)
            HotkeyMapStore.save(map)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

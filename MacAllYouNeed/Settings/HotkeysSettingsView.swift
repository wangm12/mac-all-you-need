import Platform
import SwiftUI

struct HotkeysSettingsView: View {
    let controller: AppController
    @State private var map: [HotkeyAction: HotkeyDescriptor]
    @State private var errorMessage: String?

    init(controller: AppController) {
        self.controller = controller
        _map = State(initialValue: HotkeyMapStore.load())
    }

    var body: some View {
        Form {
            ForEach(HotkeyAction.allCases) { action in
                HStack {
                    Text(action.label)
                    Spacer()
                    HotkeyRecorder(descriptor: Binding(
                        get: { map[action] ?? .defaultClipboard },
                        set: { map[action] = $0 }
                    ))
                    .frame(width: 100, height: 24)
                }
            }
            HStack {
                Spacer()
                Button("Apply") { apply() }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
        }.padding()
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

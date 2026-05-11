import SwiftUI

struct RenameCardSheet: View {
    let item: DockItem
    @Binding var isPresented: Bool
    let onSave: (String) -> Void

    @State private var label: String

    init(item: DockItem, isPresented: Binding<Bool>, onSave: @escaping (String) -> Void) {
        self.item = item
        _isPresented = isPresented
        self.onSave = onSave
        // Pre-fill with the current rename if any, otherwise leave blank so
        // the user types a fresh label rather than editing the auto-preview.
        _label = State(initialValue: item.customLabel ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Card").font(.headline)

            TextField("Label (leave empty to clear)", text: $label)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func commit() {
        onSave(label)
        isPresented = false
    }
}

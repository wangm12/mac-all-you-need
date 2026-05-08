import Core
import SwiftUI

struct SnippetSheet: View {
    let editing: Snippet?
    let onSave: (String, String, String?) -> Void
    @Binding var isPresented: Bool

    @State private var name: String
    @State private var snippetBody: String
    @State private var trigger: String

    init(
        editing: Snippet?,
        isPresented: Binding<Bool>,
        onSave: @escaping (String, String, String?) -> Void
    ) {
        self.editing = editing
        self.onSave = onSave
        _isPresented = isPresented
        _name = State(initialValue: editing?.name ?? "")
        _snippetBody = State(initialValue: editing?.body ?? "")
        _trigger = State(initialValue: editing?.trigger ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editing == nil ? "New Snippet" : "Edit Snippet")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $snippetBody)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .border(Color.secondary.opacity(0.3))

            TextField("Trigger (optional, e.g. ;sig)", text: $trigger)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Spacer()
                Button("Save") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedBody = snippetBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty, !trimmedBody.isEmpty else { return }
                    onSave(trimmedName, snippetBody, trimmedTrigger.isEmpty ? nil : trimmedTrigger)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

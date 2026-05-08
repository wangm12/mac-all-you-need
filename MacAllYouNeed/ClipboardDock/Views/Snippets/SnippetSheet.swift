import Core
import SwiftUI

struct SnippetSheet: View {
    let editing: Snippet?
    /// Other snippets to validate the trigger against. Editing the snippet at
    /// `editing.id` is excluded by id when comparing.
    let existingSnippets: [Snippet]
    let onSave: (String, String, String?) async throws -> Void
    @Binding var isPresented: Bool

    @State private var name: String
    @State private var snippetBody: String
    @State private var trigger: String
    @State private var errorMessage: String?
    @State private var saving = false

    init(
        editing: Snippet?,
        existingSnippets: [Snippet],
        isPresented: Binding<Bool>,
        onSave: @escaping (String, String, String?) async throws -> Void
    ) {
        self.editing = editing
        self.existingSnippets = existingSnippets
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Spacer()
                Button("Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saving)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = snippetBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty."
            return
        }
        guard !trimmedBody.isEmpty else {
            errorMessage = "Body cannot be empty."
            return
        }
        // Pre-validate uniqueness so the user sees a precise message instead of
        // a generic SnippetStore SQL error from the UNIQUE(trigger) constraint.
        let canonicalTrigger: String? = trimmedTrigger.isEmpty ? nil : trimmedTrigger
        if let canonicalTrigger,
           existingSnippets.contains(where: { $0.trigger == canonicalTrigger && $0.id != editing?.id })
        {
            errorMessage = "Trigger '\(canonicalTrigger)' is already used by another snippet."
            return
        }

        saving = true
        defer { saving = false }
        do {
            try await onSave(trimmedName, snippetBody, canonicalTrigger)
            errorMessage = nil
            isPresented = false
        } catch {
            errorMessage = "Could not save snippet: \(error.localizedDescription)"
        }
    }
}

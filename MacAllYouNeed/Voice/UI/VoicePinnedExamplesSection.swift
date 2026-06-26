import Core
import SwiftUI

struct VoicePinnedExamplesSection: View {
    let controller: AppController
    @State private var examples: [VoicePinnedExample] = []
    @State private var showEditor = false
    @State private var editingExample: VoicePinnedExample?
    @State private var draftBefore = ""
    @State private var draftAfter = ""
    @State private var draftStarred = false
    @State private var errorMessage: String?

    var body: some View {
        MAYNSection(
            title: "Cleanup examples",
            subtitle: "Pinned before/after pairs are always included in AI cleanup (in addition to automatic learning)."
        ) {
            if examples.isEmpty {
                MAYNSettingsRow(
                    title: "No pinned examples",
                    subtitle: "Add pairs like “gonna” → “going to” for consistent cleanup."
                ) {
                    MAYNButton("Add…") { beginAdd() }
                }
            } else {
                ForEach(Array(examples.enumerated()), id: \.element.id) { index, example in
                    pinnedRow(example)
                    if index < examples.count - 1 { MAYNDivider() }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Add another example") {
                    MAYNButton("Add…") { beginAdd() }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
    }

    private func pinnedRow(_ example: VoicePinnedExample) -> some View {
        HStack(alignment: .top, spacing: MAYNControlMetrics.rowControlSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before: \(example.before)")
                    .font(.callout)
                    .lineLimit(2)
                Text("After: \(example.after)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if example.isStarred {
                    Label("Starred", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                MAYNButton("Edit", height: 24) { beginEdit(example) }
                MAYNButton("Delete", role: .destructive, height: 24) { deleteExample(example) }
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
    }

    private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingExample == nil ? "Add cleanup example" : "Edit cleanup example")
                .font(.title3.weight(.semibold))

            MAYNTextField(placeholder: "Before (raw cleanup input)", text: $draftBefore, width: 420)
            MAYNTextField(placeholder: "After (how you want it)", text: $draftAfter, width: 420)

            Toggle("Star (keep during retention)", isOn: $draftStarred)

            HStack {
                Spacer()
                MAYNButton("Cancel") { showEditor = false }
                MAYNButton("Save", role: .primary) { saveDraft() }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func beginAdd() {
        editingExample = nil
        draftBefore = ""
        draftAfter = ""
        draftStarred = false
        showEditor = true
    }

    private func beginEdit(_ example: VoicePinnedExample) {
        editingExample = example
        draftBefore = example.before
        draftAfter = example.after
        draftStarred = example.isStarred
        showEditor = true
    }

    private func saveDraft() {
        do {
            if let editingExample {
                try controller.updatePinnedExample(
                    id: editingExample.id,
                    before: draftBefore,
                    after: draftAfter,
                    isStarred: draftStarred
                )
            } else {
                let contextID = try controller.globalPersonalizationContextID()
                _ = try controller.addPinnedExample(VoicePinnedExampleDraft(
                    contextID: contextID,
                    before: draftBefore,
                    after: draftAfter,
                    isStarred: draftStarred
                ))
            }
            showEditor = false
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteExample(_ example: VoicePinnedExample) {
        do {
            try controller.deletePinnedExample(id: example.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        if let contextID = try? controller.globalPersonalizationContextID() {
            examples = controller.listPinnedExamples(contextID: contextID)
        } else {
            examples = []
        }
        errorMessage = nil
    }
}

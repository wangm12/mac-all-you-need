import Core
import SwiftUI

enum VoiceDictionaryFilter: String, CaseIterable, Identifiable {
    case all
    case autoAdded
    case manuallyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .autoAdded:
            "Auto-added"
        case .manuallyAdded:
            "Manually-added"
        }
    }

    var symbolName: String? {
        switch self {
        case .all:
            nil
        case .autoAdded:
            "sparkles"
        case .manuallyAdded:
            "pencil"
        }
    }
}

enum VoiceDictionaryPresentation {
    static func filtered(
        _ entries: [VoiceDictionaryEntry],
        query: String,
        filter: VoiceDictionaryFilter
    ) -> [VoiceDictionaryEntry] {
        let scoped: [VoiceDictionaryEntry]
        switch filter {
        case .all, .manuallyAdded:
            scoped = entries
        case .autoAdded:
            scoped = []
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return scoped }

        return scoped.filter { entry in
            entry.phrase.localizedCaseInsensitiveContains(trimmedQuery)
                || entry.replacement.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

struct VoiceDictionaryPage: View {
    let controller: AppController
    var onBack: (() -> Void)?

    @State private var entries: [VoiceDictionaryEntry] = []
    @State private var filter: VoiceDictionaryFilter = .all
    @State private var searchText = ""
    @State private var draft = VoiceDictionaryDraft()
    @State private var isShowingEditor = false
    @State private var errorMessage: String?

    private var filteredEntries: [VoiceDictionaryEntry] {
        VoiceDictionaryPresentation.filtered(entries, query: searchText, filter: filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            VoiceDictionaryHeader(
                onBack: onBack,
                onNewWord: beginNewWord
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 14) {
                        VoiceDictionaryFilterStrip(selection: $filter)
                        Spacer(minLength: 12)
                        VoiceDictionarySearchField(text: $searchText)
                    }

                    if let errorMessage {
                        StatusPill(text: errorMessage, kind: .danger)
                    }

                    if filteredEntries.isEmpty {
                        VoiceDictionaryEmptyState(
                            title: emptyTitle,
                            subtitle: emptySubtitle
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 110)
                    } else {
                        VoiceDictionaryEntriesSection(
                            entries: filteredEntries,
                            onEdit: beginEditing,
                            onDelete: delete
                        )
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .background(MAYNTheme.window)
        .onAppear(perform: reload)
        .sheet(isPresented: $isShowingEditor) {
            VoiceDictionaryEditorSheet(
                draft: $draft,
                onCancel: { isShowingEditor = false },
                onSave: saveDraft
            )
        }
    }

    private var emptyTitle: String {
        if filter == .autoAdded { return "No auto-added words yet" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matching words" }
        return "No words yet"
    }

    private var emptySubtitle: String {
        if filter == .autoAdded {
            return "Automatic learning from edits is not stored yet. Manual dictionary entries are available now."
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different word, name, or replacement."
        }
        return "Mac All You Need remembers names, product terms, and ASR corrections you add manually."
    }

    private func reload() {
        entries = controller.listVoiceDictionaryEntries()
    }

    private func beginNewWord() {
        draft = VoiceDictionaryDraft()
        errorMessage = nil
        isShowingEditor = true
    }

    private func beginEditing(_ entry: VoiceDictionaryEntry) {
        draft = VoiceDictionaryDraft(entry: entry)
        errorMessage = nil
        isShowingEditor = true
    }

    private func saveDraft() {
        let phrase = draft.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !replacement.isEmpty else {
            errorMessage = "Phrase and replacement are required."
            return
        }

        do {
            if let id = draft.id,
               let original = entries.first(where: { $0.id == id }),
               original.phrase != phrase {
                try controller.deleteVoiceDictionaryEntry(id: id)
            }
            try controller.upsertVoiceDictionaryEntry(phrase: phrase, replacement: replacement)
            isShowingEditor = false
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ entry: VoiceDictionaryEntry) {
        do {
            try controller.deleteVoiceDictionaryEntry(id: entry.id)
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VoiceDictionaryDraft {
    var id: String?
    var phrase = ""
    var replacement = ""

    init() {}

    init(entry: VoiceDictionaryEntry) {
        id = entry.id
        phrase = entry.phrase
        replacement = entry.replacement
    }
}

private struct VoiceDictionaryHeader: View {
    let onBack: (() -> Void)?
    let onNewWord: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(MAYNTheme.panel, in: Circle())
                .overlay(Circle().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Dictionary")
                    .font(.system(size: 26, weight: .semibold))
                Text("Teach voice dictation names, terms, and recurring corrections.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("New word", action: onNewWord)
                .buttonStyle(VoiceDictionaryPrimaryButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }
}

private struct VoiceDictionaryFilterStrip: View {
    @Binding var selection: VoiceDictionaryFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VoiceDictionaryFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    HStack(spacing: 5) {
                        if let symbolName = filter.symbolName {
                            Image(systemName: symbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(filter == .autoAdded ? MAYNTheme.success : .secondary)
                        }
                        Text(filter.title)
                            .font(.callout)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        selection == filter ? MAYNTheme.window : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == filter ? .primary : .secondary)
            }
        }
        .padding(3)
        .background(MAYNTheme.panel, in: Capsule())
    }
}

private struct VoiceDictionarySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 34)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

private struct VoiceDictionaryEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}

private struct VoiceDictionaryEntriesSection: View {
    let entries: [VoiceDictionaryEntry]
    let onEdit: (VoiceDictionaryEntry) -> Void
    let onDelete: (VoiceDictionaryEntry) -> Void

    var body: some View {
        MAYNSection(title: "Words", subtitle: "\(entries.count) entries") {
            ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                if offset > 0 { MAYNDivider() }
                VoiceDictionaryEntryRow(
                    entry: entry,
                    onEdit: { onEdit(entry) },
                    onDelete: { onDelete(entry) }
                )
            }
        }
    }
}

private struct VoiceDictionaryEntryRow: View {
    let entry: VoiceDictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.phrase)
                    .font(.callout.weight(.medium))
                Text(entry.replacement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Edit", action: onEdit)
                .buttonStyle(.borderless)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .onHover { isHovering = $0 }
    }
}

private struct VoiceDictionaryEditorSheet: View {
    @Binding var draft: VoiceDictionaryDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        !draft.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(draft.id == nil ? "New word" : "Edit word")
                    .font(.system(size: 20, weight: .semibold))
                Text("Replace a recurring misrecognition before cleanup and paste.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Heard phrase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Example: 海涛", text: $draft.phrase)
                    .textFieldStyle(.roundedBorder)
                Text("Replacement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Example: 江涛", text: $draft.replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

private struct VoiceDictionaryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(Color.black.opacity(configuration.isPressed ? 0.78 : 0.92), in: Capsule())
    }
}

import Core
import SwiftUI

enum VoiceDictionaryFilter: String, SegmentedTabDestination {
    case all
    case autoAdded
    case manuallyAdded

    var title: String {
        switch self {
        case .all:
            "All"
        case .autoAdded:
            "Auto"
        case .manuallyAdded:
            "Manual"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            "textformat"
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
    let showsHeader: Bool
    let onBack: (() -> Void)?

    @State private var entries: [VoiceDictionaryEntry] = []
    @State private var filter: VoiceDictionaryFilter = .all
    @State private var searchText = ""
    @State private var draft = VoiceDictionaryDraft()
    @State private var isShowingEditor = false
    @State private var errorMessage: String?

    private var filteredEntries: [VoiceDictionaryEntry] {
        VoiceDictionaryPresentation.filtered(entries, query: searchText, filter: filter)
    }

    init(
        controller: AppController,
        showsHeader: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.controller = controller
        self.showsHeader = showsHeader
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                VoiceDictionaryHeader(
                    onBack: onBack
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VoiceDictionaryActionBar(
                        filter: $filter,
                        searchText: $searchText,
                        onNewWord: beginNewWord
                    )

                    if let errorMessage {
                        StatusPill(text: errorMessage, kind: .danger)
                    }

                    if filteredEntries.isEmpty {
                        VoiceDictionaryEmptyState(
                            title: emptyTitle,
                            subtitle: emptySubtitle,
                            actionTitle: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New word" : nil,
                            action: beginNewWord
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        VoiceDictionaryEntriesSection(
                            entries: filteredEntries,
                            onEdit: beginEditing,
                            onDelete: delete
                        )
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, showsHeader ? 18 : 26)
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
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }
}

private struct VoiceDictionaryActionBar: View {
    @Binding var filter: VoiceDictionaryFilter
    @Binding var searchText: String
    let onNewWord: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FunctionSegmentedTabStrip(
                tabs: VoiceDictionaryFilter.allCases,
                selection: filter,
                fillsAvailableWidth: false,
                size: .control
            ) { nextFilter in
                filter = nextFilter
            }

            VoiceDictionarySearchField(text: $searchText)
                .frame(maxWidth: 280)

            Spacer(minLength: 12)

            MAYNButton(role: .primary, height: MAYNControlMetrics.controlHeight, action: onNewWord) {
                Label("New word", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(10)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

private struct VoiceDictionarySearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MAYNControlMetrics.controlHeight)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isFocused ? MAYNTheme.focusRing : MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

private struct VoiceDictionaryEmptyState: View {
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle {
                MAYNButton(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

private struct VoiceDictionaryEntriesSection: View {
    let entries: [VoiceDictionaryEntry]
    let onEdit: (VoiceDictionaryEntry) -> Void
    let onDelete: (VoiceDictionaryEntry) -> Void

    var body: some View {
        MAYNSection(title: "Words", subtitle: "\(entries.count) \(entries.count == 1 ? "entry" : "entries")") {
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.phrase)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text(entry.replacement)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(VoiceDictionaryIconButtonStyle())
                .help("Edit word")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(VoiceDictionaryIconButtonStyle(role: .destructive))
                .help("Delete word")
            }
            .opacity(isHovering ? 1 : 0.68)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct VoiceDictionaryIconButtonStyle: ButtonStyle {
    enum Role {
        case normal
        case destructive
    }

    var role: Role = .normal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 28, height: 28)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.11 : 0.06),
                in: Circle()
            )
    }

    private var foregroundColor: Color {
        switch role {
        case .normal:
            .secondary
        case .destructive:
            MAYNTheme.danger
        }
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
                MAYNTextField(placeholder: "Example: 海涛", text: $draft.phrase, width: 376)
                Text("Replacement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                MAYNTextField(placeholder: "Example: 江涛", text: $draft.replacement, width: 376)
            }

            HStack {
                Spacer()
                MAYNButton("Cancel", action: onCancel)
                MAYNButton("Save", role: .primary, action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

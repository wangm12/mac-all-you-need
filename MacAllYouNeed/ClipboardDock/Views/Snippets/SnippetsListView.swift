import Core
import SwiftUI

enum DockSnippetEditorMode: Identifiable {
    case new
    case draft(SnippetDraft)
    case edit(RecordID)

    var id: String {
        switch self {
        case .new:
            return "new"
        case let .draft(draft):
            return "draft-\(draft.id.uuidString)"
        case let .edit(id):
            return id.rawValue
        }
    }
}

struct DockSnippetsListView: View {
    @Bindable var model: ClipboardDockModel
    @Binding var editorMode: DockSnippetEditorMode?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                Button {
                    editorMode = .new
                } label: {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                        Text("New Snippet")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .modifier(SnippetCardShell(isFocused: false, alignment: .center))
                }
                .buttonStyle(.plain)

                ForEach(Array(model.snippetItems.enumerated()), id: \.element.id) { index, snippet in
                    SnippetCard(
                        snippet: snippet,
                        isFocused: index == model.focusedIndex,
                        onPaste: { plainText in
                            model.focusedIndex = index
                            Task {
                                await model.pasteSnippet(id: snippet.id, plainText: plainText)
                            }
                        },
                        onEdit: {
                            editorMode = .edit(snippet.id)
                        },
                        onDuplicate: {
                            Task {
                                await model.duplicateSnippet(id: snippet.id)
                            }
                        },
                        onDelete: {
                            Task {
                                await model.deleteSnippet(id: snippet.id)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .task {
            await model.loadSnippets()
            presentPendingSnippetDraft()
        }
        .onChange(of: model.pendingSnippetDraft?.id) { _, _ in
            presentPendingSnippetDraft()
        }
    }

    private func presentPendingSnippetDraft() {
        guard let draft = model.pendingSnippetDraft else { return }
        editorMode = .draft(draft)
    }
}

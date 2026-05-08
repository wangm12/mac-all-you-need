import Core
import SwiftUI

struct DockSnippetsListView: View {
    @Bindable var model: ClipboardDockModel
    @State private var sheetMode: SheetMode?

    enum SheetMode: Identifiable {
        case new
        case edit(RecordID)

        var id: String {
            switch self {
            case .new:
                return "new"
            case let .edit(id):
                return id.rawValue
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                Button {
                    sheetMode = .new
                } label: {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                        Text("New Snippet")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 220, height: 240)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
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
                            sheetMode = .edit(snippet.id)
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
        }
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .new:
                SnippetSheet(
                    editing: nil,
                    isPresented: bindingForSheet,
                    onSave: { name, body, trigger in
                        Task {
                            await model.createSnippet(name: name, body: body, trigger: trigger)
                        }
                    }
                )

            case let .edit(id):
                SnippetSheet(
                    editing: model.snippetItems.first(where: { $0.id == id }),
                    isPresented: bindingForSheet,
                    onSave: { name, body, trigger in
                        Task {
                            await model.updateSnippet(id: id, name: name, body: body, trigger: trigger)
                        }
                    }
                )
            }
        }
    }

    private var bindingForSheet: Binding<Bool> {
        Binding(
            get: { sheetMode != nil },
            set: { visible in
                if !visible {
                    sheetMode = nil
                }
            }
        )
    }
}

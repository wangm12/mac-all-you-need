import Platform
import SwiftUI

struct MultiSelectBar: View {
    @Bindable var model: ClipboardDockModel
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(model.selection.count) selected")
                .font(.callout)
            Spacer()

            Button("Paste") {
                Task {
                    await model.pasteSelectionInOrder(delimiter: "\n", plainText: false)
                }
            }

            Button("Paste plain") {
                Task {
                    await model.pasteSelectionInOrder(delimiter: "\n", plainText: true)
                }
            }

            Button("Pin", action: onPin)

            Menu("Add to list") {
                if model.availableLists.isEmpty {
                    Text("No lists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.availableLists, id: \.id) { board in
                        Button(board.name) {
                            Task {
                                await model.addToPinboard(
                                    itemIDs: Array(model.selection),
                                    boardID: board.id
                                )
                                model.clearSelection()
                            }
                        }
                    }
                }
            }

            Menu("Transform") {
                ForEach(TextTransform.allCases, id: \.self) { transform in
                    Button(label(for: transform)) {
                        Task {
                            await model.applyTransform(transform, saveAsNew: true)
                        }
                    }
                }
            }

            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteSelected()
                }
            }

            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    private func label(for transform: TextTransform) -> String {
        switch transform {
        case .lowercase: return "Lowercase"
        case .uppercase: return "Uppercase"
        case .titleCase: return "Title Case"
        case .trim: return "Trim"
        case .stripHTML: return "Strip HTML"
        case .prettyJSON: return "Pretty JSON"
        case .minifyJSON: return "Minify JSON"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .sortLines: return "Sort Lines"
        case .dedupeLines: return "Dedupe Lines"
        }
    }
}

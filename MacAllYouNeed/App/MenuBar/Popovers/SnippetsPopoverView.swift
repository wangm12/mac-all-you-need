import AppKit
import Core
import SwiftUI

/// Named `SnippetsListView` to preserve the call site in `MainWindowRoot.swift`.
struct SnippetsListView: View {
    @Bindable var model: ClipboardDockModel
    let controller: AppController?

    init(model: ClipboardDockModel, controller: AppController? = nil) {
        self._model = Bindable(wrappedValue: model)
        self.controller = controller
    }

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                popoverHeader(controller: controller)
            }
            Group {
                if model.snippetItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(MAYNTheme.selected, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))

                        VStack(spacing: 3) {
                            Text("No snippets yet")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Open the clipboard dock to create reusable text.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                    .padding(12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.snippetItems, id: \.id) { snippet in
                                HStack(spacing: 10) {
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 30, height: 30)
                                        .background(Color.primary.opacity(0.08), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(snippet.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(SnippetsListPresentation.menuBodyPreview(for: snippet))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary.opacity(0.82))
                                            .lineLimit(2)
                                        if let trigger = snippet.trigger {
                                            Text(trigger)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    DownloadIconButton(
                                        symbolName: "doc.on.doc",
                                        role: .secondary,
                                        accessibilityLabel: "Copy",
                                        action: { copySnippet(snippet) }
                                    )
                                    .help("Copy snippet")
                                }
                                .padding(10)
                                .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                                )
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .task { await model.loadSnippets() }
    }

    private func popoverHeader(controller: AppController) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Snippets")
                    .font(.headline.weight(.semibold))
                Text("Copy reusable text here, or open the full Clipboard page to create and manage snippets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            MAYNButton("Open Clipboard", role: .primary, height: HotkeyChipPresentation.compactHeight) {
                controller.showMainWindow(destination: .clipboard)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(MAYNTheme.panel)
    }

    private func copySnippet(_ snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.body, forType: .string)
        NotificationCenter.default.post(name: .menuBarPopoverDismissRequested, object: nil)
        CopyHUD.show("Copied")
    }
}

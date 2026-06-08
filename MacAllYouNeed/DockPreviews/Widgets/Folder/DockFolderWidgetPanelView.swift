import AppKit
import SwiftUI

/// Full folder stack preview with navigation, sort, and permissions (DockDoor `FolderWidgetPanelView` subset).
struct DockFolderWidgetPanelView: View {
    @ObservedObject var model: DockFolderWidgetModel
    let onDismissPreview: () -> Void

    private let contentHeight: CGFloat = 280
    private let panelWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 10) {
            header
            sortControls
            content
        }
        .frame(width: panelWidth)
        .task(id: taskKey) { await model.reload() }
        .onChange(of: model.showHiddenFiles) { _, _ in
            Task { await model.reload() }
        }
    }

    private var taskKey: String {
        "\(model.currentURL.path)|\(model.showHiddenFiles)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.currentURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentName)
                    .font(.headline)
                    .lineLimit(1)
                Text("Folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                DockFolderWidgetActions.openInFinder(url: model.currentURL)
                onDismissPreview()
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Open in Finder")
        }
    }

    private var sortControls: some View {
        HStack(spacing: 6) {
            if !model.navigationStack.isEmpty {
                Button { model.popDirectory() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Back")
            }

            Menu {
                ForEach(DockFolderSortOrder.allCases) { order in
                    Button {
                        model.setSortOrder(order)
                    } label: {
                        if order == model.sortOrder {
                            Label(order.displayName, systemImage: "checkmark")
                        } else {
                            Text(order.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.sortOrder.displayName)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)

            Button {
                model.setSortReversed(!model.sortReversed)
            } label: {
                Image(systemName: model.sortReversed ? "arrow.down" : "arrow.up")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MAYNTheme.hover)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch model.accessState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight)
        case .accessible:
            if model.displayItems.isEmpty {
                stateView(
                    systemName: "folder",
                    title: "Empty folder",
                    message: "There are no visible items in this folder."
                )
            } else {
                itemList
            }
        case .permissionDenied:
            stateView(
                systemName: "lock.fill",
                title: "Permission needed",
                message: "Grant access to view this folder's contents.",
                actionTitle: "Grant Access",
                action: { model.requestAccess() }
            )
        case .missing:
            stateView(
                systemName: "exclamationmark.triangle",
                title: "Folder missing",
                message: "This folder could not be found."
            )
        case .failed:
            stateView(
                systemName: "exclamationmark.triangle",
                title: "Could not load",
                message: "Try again or open the folder in Finder."
            )
        }
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.displayItems) { item in
                    itemRow(item)
                }
            }
        }
        .frame(height: contentHeight)
    }

    private func itemRow(_ item: DockFolderWidgetItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                if !item.localizedKind.isEmpty {
                    Text(item.localizedKind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            model.openItem(item)
        }
        .contextMenu {
            if item.isDirectory {
                Button("Open") { model.openItem(item) }
            } else {
                Button("Open") { model.openItem(item) }
            }
            Divider()
            Button("Open in Finder") {
                DockFolderWidgetActions.openInFinder(url: item.url)
            }
            Button("Browse in Mac All You Need") {
                DockFolderWidgetActions.browseInApp(url: item.isDirectory ? item.url : item.url.deletingLastPathComponent())
                onDismissPreview()
            }
            Button("Add to Folder History") {
                DockFolderWidgetActions.addToFolderHistory(path: item.url.path)
            }
        }
    }

    private func stateView(
        systemName: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                MAYNButton(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentHeight)
        .padding()
    }
}

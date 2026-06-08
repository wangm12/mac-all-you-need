import SwiftUI

/// Dock folder stack preview entry point.
struct DockFolderWidgetView: View {
    let title: String
    let url: URL
    let showHidden: Bool
    var onDismissPreview: () -> Void = {}

    @StateObject private var model: DockFolderWidgetModel

    init(
        title: String,
        url: URL,
        showHidden: Bool,
        onDismissPreview: @escaping () -> Void = {}
    ) {
        self.title = title
        self.url = url
        self.showHidden = showHidden
        self.onDismissPreview = onDismissPreview
        let hub = DockHubSettingsStore.load()
        _model = StateObject(wrappedValue: DockFolderWidgetModel(
            rootURL: url,
            rootName: title,
            sortOrder: hub.widgets.folderSortOrder,
            sortReversed: hub.widgets.folderSortReversed,
            showHiddenFiles: showHidden,
            rememberSortPerFolder: hub.widgets.folderRememberSortPerFolder,
            perFolderSortOrders: hub.widgets.folderSortOrders,
            perFolderSortReversed: hub.widgets.folderSortReversedByPath
        ))
    }

    var body: some View {
        DockFolderWidgetPanelView(model: model, onDismissPreview: onDismissPreview)
    }
}

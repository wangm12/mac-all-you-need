import Core
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardDockModel {
    let xpc: any ClipboardXPCInteracting
    let appIcons: AppIconResolver
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader

    var items: [DockItem] = []
    var search: String = ""
    var focusedIndex: Int = 0
    var activeList: DockListSelector = .history
    private var refreshDebounceTask: Task<Void, Never>?
    private var refreshSequence: UInt64 = 0

    init(
        xpc: any ClipboardXPCInteracting,
        appIcons: AppIconResolver,
        imageLoader: ImageBlobLoader,
        fileLoader: FileURLLoader
    ) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
    }

    func refresh() async {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        let sequence = nextRefreshSequence()
        await performRefresh(sequence: sequence)
    }

    func refreshDebounced() {
        refreshDebounceTask?.cancel()
        let sequence = nextRefreshSequence()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self?.performRefresh(sequence: sequence)
        }
    }

    private func nextRefreshSequence() -> UInt64 {
        refreshSequence += 1
        return refreshSequence
    }

    private func performRefresh(sequence: UInt64) async {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = trimmed.isEmpty ? nil : trimmed
        let list = await xpc.listItems(query: query, pageToken: nil, limit: 50)
        guard sequence == refreshSequence else { return }

        let previousID: String? = items.indices.contains(focusedIndex)
            ? items[focusedIndex].id
            : nil

        items = list.items.map { meta in
            let app: SourceApp? = meta.sourceAppBundleID.map {
                SourceApp(
                    bundleID: $0,
                    displayName: appIcons.displayName(for: $0),
                    icon: appIcons.icon(for: $0)
                )
            }
            return DockItem(from: meta, sourceApp: app, isPinned: false)
        }

        if let previousID, let newIdx = items.firstIndex(where: { $0.id == previousID }) {
            focusedIndex = newIdx
        } else {
            focusedIndex = 0
        }
    }

    func focusForward() {
        guard !items.isEmpty else { return }
        focusedIndex = min(items.count - 1, focusedIndex + 1)
    }

    func focusBackward() {
        guard !items.isEmpty else { return }
        focusedIndex = max(0, focusedIndex - 1)
    }
}

import AppKit
import Foundation

struct DockFolderWidgetItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let modifiedDate: Date
    let size: Int64
    let localizedKind: String

    var id: String { url.path }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum DockFolderWidgetAccessState: Equatable {
    case loading
    case accessible([DockFolderWidgetItem])
    case permissionDenied
    case missing
    case failed
}

struct DockFolderWidgetLevel: Equatable {
    let url: URL
    let name: String
}

enum DockFolderWidgetLoader {
    static func loadItems(from url: URL, showHiddenFiles: Bool) async -> DockFolderWidgetAccessState {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: url.path) else { return .missing }

            let readURL = DockFolderWidgetBookmarkStore.accessibleURL(for: url)
            guard let readURL else {
                if fileManager.isReadableFile(atPath: url.path) {
                    return .permissionDenied
                }
                return .permissionDenied
            }

            let didStart = readURL.startAccessingSecurityScopedResource()
            defer {
                if didStart { readURL.stopAccessingSecurityScopedResource() }
            }

            let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
            do {
                let urls = try fileManager.contentsOfDirectory(
                    at: readURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .totalFileAllocatedSizeKey,
                        .localizedTypeDescriptionKey,
                    ],
                    options: options
                )
                let items = urls.compactMap { itemURL -> DockFolderWidgetItem? in
                    let values = try? itemURL.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .totalFileAllocatedSizeKey,
                        .localizedTypeDescriptionKey,
                    ])
                    return DockFolderWidgetItem(
                        url: itemURL,
                        name: itemURL.lastPathComponent,
                        isDirectory: values?.isDirectory ?? false,
                        modifiedDate: values?.contentModificationDate ?? .distantPast,
                        size: Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0),
                        localizedKind: values?.localizedTypeDescription ?? ""
                    )
                }
                return .accessible(items)
            } catch let error as NSError where error.code == NSFileReadNoPermissionError {
                return .permissionDenied
            } catch {
                return .failed
            }
        }.value
    }

    static func sortedItems(
        _ items: [DockFolderWidgetItem],
        order: DockFolderSortOrder,
        reversed: Bool
    ) -> [DockFolderWidgetItem] {
        let sorted: [DockFolderWidgetItem]
        switch order {
        case .name:
            sorted = items.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .kind:
            sorted = items.sorted {
                let c = $0.localizedKind.localizedCaseInsensitiveCompare($1.localizedKind)
                if c == .orderedSame {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return c == .orderedAscending
            }
        case .size:
            sorted = items.sorted {
                if $0.size == $1.size {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.size < $1.size
            }
        case .dateModified:
            sorted = items.sorted {
                if $0.modifiedDate == $1.modifiedDate {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.modifiedDate < $1.modifiedDate
            }
        }
        return reversed ? sorted.reversed() : sorted
    }
}

@MainActor
final class DockFolderWidgetModel: ObservableObject {
    let rootURL: URL
    let rootName: String

    @Published private(set) var accessState: DockFolderWidgetAccessState = .loading
    @Published var navigationStack: [DockFolderWidgetLevel] = []
    @Published var sortOrder: DockFolderSortOrder
    @Published var sortReversed: Bool
    @Published var showHiddenFiles: Bool

    var currentURL: URL {
        navigationStack.last?.url ?? rootURL
    }

    var currentName: String {
        navigationStack.last?.name ?? rootName
    }

    var displayItems: [DockFolderWidgetItem] {
        guard case let .accessible(items) = accessState else { return [] }
        return DockFolderWidgetLoader.sortedItems(items, order: sortOrder, reversed: sortReversed)
    }

    init(
        rootURL: URL,
        rootName: String,
        sortOrder: DockFolderSortOrder,
        sortReversed: Bool,
        showHiddenFiles: Bool,
        rememberSortPerFolder: Bool,
        perFolderSortOrders: [String: String],
        perFolderSortReversed: [String: Bool]
    ) {
        self.rootURL = rootURL
        self.rootName = rootName
        self.showHiddenFiles = showHiddenFiles
        self.rememberSortPerFolder = rememberSortPerFolder
        self.perFolderSortOrders = perFolderSortOrders
        self.perFolderSortReversed = perFolderSortReversed
        if rememberSortPerFolder, let raw = perFolderSortOrders[rootURL.path],
           let order = DockFolderSortOrder(rawValue: raw) {
            self.sortOrder = order
            self.sortReversed = perFolderSortReversed[rootURL.path] ?? sortReversed
        } else {
            self.sortOrder = sortOrder
            self.sortReversed = sortReversed
        }
    }

    private let rememberSortPerFolder: Bool
    private var perFolderSortOrders: [String: String]
    private var perFolderSortReversed: [String: Bool]

    func reload() async {
        accessState = .loading
        accessState = await DockFolderWidgetLoader.loadItems(from: currentURL, showHiddenFiles: showHiddenFiles)
    }

    func pushDirectory(_ item: DockFolderWidgetItem) {
        guard item.isDirectory else { return }
        navigationStack.append(DockFolderWidgetLevel(url: item.url, name: item.name))
        if rememberSortPerFolder, let raw = perFolderSortOrders[item.url.path],
           let order = DockFolderSortOrder(rawValue: raw) {
            sortOrder = order
            sortReversed = perFolderSortReversed[item.url.path] ?? sortReversed
        }
        Task { await reload() }
    }

    func popDirectory() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        let url = currentURL
        if rememberSortPerFolder, let raw = perFolderSortOrders[url.path],
           let order = DockFolderSortOrder(rawValue: raw) {
            sortOrder = order
            sortReversed = perFolderSortReversed[url.path] ?? sortReversed
        }
        Task { await reload() }
    }

    func setSortOrder(_ order: DockFolderSortOrder) {
        sortOrder = order
        if rememberSortPerFolder {
            perFolderSortOrders[currentURL.path] = order.rawValue
            persistPerFolderSort()
        }
    }

    func setSortReversed(_ reversed: Bool) {
        sortReversed = reversed
        if rememberSortPerFolder {
            perFolderSortReversed[currentURL.path] = reversed
            persistPerFolderSort()
        }
    }

    private func persistPerFolderSort() {
        var hub = DockHubSettingsStore.load()
        hub.widgets.folderSortOrders = perFolderSortOrders
        hub.widgets.folderSortReversedByPath = perFolderSortReversed
        DockHubSettingsStore.save(hub)
    }

    func requestAccess() {
        if let granted = DockFolderWidgetBookmarkStore.requestAccess(to: currentURL) {
            _ = granted
            Task { await reload() }
        }
    }

    func openItem(_ item: DockFolderWidgetItem) {
        if item.isDirectory {
            pushDirectory(item)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}

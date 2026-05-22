import AppKit
import Core
import Platform

// MARK: - PreviewRow

struct PreviewRow {
    let name: String
    let path: String
    let kind: String
    let size: Int64
    let sizeText: String
    let modified: Date?
    let modifiedText: String
    let isDirectory: Bool
    let filterKind: FolderEntryKind?
    let url: URL?
    let supportsThumbnail: Bool

    init(entry: FolderEntry) {
        name = entry.name
        path = entry.path
        kind = FolderPreviewDisplay.displayKind(for: entry)
        size = entry.size
        sizeText = entry.isDirectory ? "—" : ByteCountFormatter.preview.string(fromByteCount: entry.size)
        modified = entry.modified == .distantPast ? nil : entry.modified
        modifiedText = entry.modified == .distantPast ? "—" : DateFormatter.preview.string(from: entry.modified)
        isDirectory = entry.isDirectory
        filterKind = entry.kind
        url = URL(fileURLWithPath: entry.path)
        supportsThumbnail = FolderPreviewDisplay.canGenerateThumbnail(for: entry)
    }

    init(archiveEntry: ArchiveEntry) {
        name = archiveEntry.path
        path = archiveEntry.path
        kind = archiveEntry.isDirectory ? "Folder" : "Archive item"
        size = archiveEntry.uncompressedSize
        sizeText = archiveEntry.isDirectory ? "—" : ByteCountFormatter.preview.string(fromByteCount: archiveEntry.uncompressedSize)
        modified = archiveEntry.modified
        modifiedText = archiveEntry.modified.map(DateFormatter.preview.string(from:)) ?? "—"
        isDirectory = archiveEntry.isDirectory
        filterKind = nil
        url = nil
        supportsThumbnail = false
    }
}

// MARK: - FolderPreviewNode

final class FolderPreviewNode {
    let row: PreviewRow?
    weak var parent: FolderPreviewNode?
    var children: [FolderPreviewNode]?
    var isLoading = false
    var placeholderText: String?

    init(row: PreviewRow, parent: FolderPreviewNode? = nil) {
        self.row = row
        self.parent = parent
    }

    private init(placeholderText: String, parent: FolderPreviewNode?) {
        row = nil
        self.parent = parent
        self.placeholderText = placeholderText
    }

    static func placeholder(_ text: String, parent: FolderPreviewNode?) -> FolderPreviewNode {
        FolderPreviewNode(placeholderText: text, parent: parent)
    }
}

// MARK: - PreviewOutlineDataSource

final class PreviewOutlineDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var filter: FolderPreviewFilter = .all
    var onSelectionChange: ((PreviewRow?) -> Void)?
    private var cascade = true
    private var rootNodes: [FolderPreviewNode] = []
    private let iconCache = FolderIconCache()
    private var loadTasksByPath: [String: Task<Void, Never>] = [:]
    private var generation = 0

    var visibleRootCount: Int {
        children(of: nil).count
    }

    func configure(rootNodes: [FolderPreviewNode], filter: FolderPreviewFilter, cascade: Bool) {
        reset()
        self.rootNodes = rootNodes
        self.filter = filter
        self.cascade = cascade
    }

    func reset() {
        loadTasksByPath.values.forEach { $0.cancel() }
        loadTasksByPath.removeAll()
        rootNodes = []
        iconCache.reset()
        generation += 1
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item as? FolderPreviewNode).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item as? FolderPreviewNode)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let row = (item as? FolderPreviewNode)?.row else { return false }
        return cascade && row.isDirectory
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard cascade else { return false }
        guard let node = item as? FolderPreviewNode else { return false }
        loadChildren(for: node, in: outlineView)
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else { return }
        let rowIndex = outlineView.selectedRow
        guard rowIndex >= 0,
              let node = outlineView.item(atRow: rowIndex) as? FolderPreviewNode else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(node.row)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FolderPreviewNode,
              let column = tableColumn?.identifier.rawValue else { return nil }

        guard let row = node.row else {
            return textCell(tableView: outlineView, text: column == PreviewColumn.name.rawValue ? node.placeholderText ?? "" : "")
        }

        switch PreviewColumn(rawValue: column) {
        case .name:
            let cell = outlineView.makeView(
                withIdentifier: NameCellView.identifier,
                owner: nil
            ) as? NameCellView ?? NameCellView()
            cell.configure(text: row.name, icon: iconCache.icon(for: row), path: row.path)
            return cell
        case .kind:
            return textCell(tableView: outlineView, text: row.kind)
        case .size:
            return textCell(tableView: outlineView, text: row.sizeText, alignment: .right)
        case .modified:
            return textCell(tableView: outlineView, text: row.modifiedText)
        case .none:
            return nil
        }
    }

    private func children(of node: FolderPreviewNode?) -> [FolderPreviewNode] {
        let nodes = node?.children ?? rootNodes
        return nodes.filter(isVisible)
    }

    private func isVisible(_ node: FolderPreviewNode) -> Bool {
        guard let row = node.row, let kind = row.filterKind else { return true }
        return FolderPreviewDisplay.matches(kind: kind, isDirectory: row.isDirectory, filter: filter)
    }

    private func loadChildren(for node: FolderPreviewNode, in outlineView: NSOutlineView) {
        guard node.children == nil,
              !node.isLoading,
              let row = node.row,
              row.isDirectory,
              let url = row.url else { return }

        node.isLoading = true
        node.children = [FolderPreviewNode.placeholder("Loading...", parent: node)]
        outlineView.reloadItem(node, reloadChildren: true)

        let taskGeneration = generation
        let path = row.path
        let task = Task {
            do {
                let inventory = try await FolderEnumerator.enumerateImmediate(url: url, maxEntries: 500)
                try Task.checkCancellation()
                let children = FolderPreviewDisplay.sorted(inventory.entries)
                    .prefix(500)
                    .map { FolderPreviewNode(row: PreviewRow(entry: $0), parent: node) }

                await MainActor.run {
                    guard self.generation == taskGeneration else { return }
                    node.isLoading = false
                    node.children = children
                    self.loadTasksByPath[path] = nil
                    outlineView.reloadItem(node, reloadChildren: true)
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard self.generation == taskGeneration else { return }
                    node.isLoading = false
                    node.children = [FolderPreviewNode.placeholder("Unable to load", parent: node)]
                    self.loadTasksByPath[path] = nil
                    outlineView.reloadItem(node, reloadChildren: true)
                }
            }
        }
        loadTasksByPath[path] = task
    }

    private func textCell(
        tableView: NSTableView,
        text: String,
        alignment: NSTextAlignment = .left
    ) -> NSTableCellView {
        let cell = tableView.makeView(withIdentifier: TextCellView.identifier, owner: nil) as? TextCellView ?? TextCellView()
        cell.configure(text: text, alignment: alignment)
        return cell
    }
}

// MARK: - PreviewTableDataSource

final class PreviewTableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [PreviewRow] = []
    var onSelectionChange: ((PreviewRow?) -> Void)?
    private let iconCache = FolderIconCache()

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let column = tableColumn?.identifier.rawValue else { return nil }
        let item = rows[row]

        switch PreviewColumn(rawValue: column) {
        case .name:
            let cell = tableView.makeView(
                withIdentifier: NameCellView.identifier,
                owner: nil
            ) as? NameCellView ?? NameCellView()
            cell.configure(text: item.name, icon: iconCache.icon(for: item), path: item.path)
            return cell
        case .kind:
            return textCell(tableView: tableView, text: item.kind)
        case .size:
            return textCell(tableView: tableView, text: item.sizeText, alignment: .right)
        case .modified:
            return textCell(tableView: tableView, text: item.modifiedText)
        case .none:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let rowIndex = tableView.selectedRow
        guard rowIndex >= 0, rowIndex < rows.count else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(rows[rowIndex])
    }

    private func textCell(
        tableView: NSTableView,
        text: String,
        alignment: NSTextAlignment = .left
    ) -> NSTableCellView {
        let cell = tableView.makeView(withIdentifier: TextCellView.identifier, owner: nil) as? TextCellView ?? TextCellView()
        cell.configure(text: text, alignment: alignment)
        return cell
    }
}

// MARK: - Formatters

extension ByteCountFormatter {
    static let preview: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter
    }()
}

extension DateFormatter {
    static let preview: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

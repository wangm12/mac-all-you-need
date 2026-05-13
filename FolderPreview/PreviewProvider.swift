import Cocoa
import Core
import ImageIO
import Platform
import Quartz
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let previewView = QuickLookPreviewView()
    private var previewTask: Task<Void, Never>?
    private var previewID = UUID()

    override func loadView() {
        view = previewView
        preferredContentSize = NSSize(width: 1080, height: 640)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewTask?.cancel()
        let id = UUID()
        previewID = id

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        previewView.configureLoading(url: url, isDirectory: isDirectory)
        handler(nil)

        previewTask = Task {
            do {
                if isDirectory {
                    let inventory = try await FolderEnumerator.enumerateImmediate(url: url, maxEntries: 500)
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.previewID == id else { return }
                        previewView.configureFolder(url: url, inventory: inventory)
                    }
                } else {
                    let entries = try await Task.detached(priority: .userInitiated) {
                        try LibArchiveBackend().list(archiveURL: url, limits: .default)
                    }.value
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.previewID == id else { return }
                        previewView.configureArchive(url: url, entries: entries)
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard self.previewID == id else { return }
                    previewView.configureError(title: url.lastPathComponent, error: error)
                }
            }
        }
    }
}

private final class QuickLookPreviewView: NSView, NSSplitViewDelegate {
    private let header = NSView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let statusBadge = NSTextField(labelWithString: "")
    private let filterBar = NSView()
    private let filterControl = NSSegmentedControl(
        labels: FolderPreviewFilter.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let divider = NSBox()
    private let splitView = NSSplitView()
    private let scrollView = NSScrollView()
    private let selectionPreviewPane = SelectionPreviewPane()
    private let tableView = PreviewTableView()
    private let outlineView = PreviewOutlineView()
    private let emptyField = NSTextField(labelWithString: "")
    private let tableDataSource = PreviewTableDataSource()
    private let outlineDataSource = PreviewOutlineDataSource()
    private var filterBarHeightConstraint: NSLayoutConstraint?
    private var selectionPreviewTask: Task<Void, Never>?
    private var selectionPreviewID = UUID()
    private var isSelectionPreviewVisible = false
    private var needsSplitPositionUpdate = false
    private var contentMode: PreviewContentMode = .table
    private var folderRootCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        selectionPreviewTask?.cancel()
    }

    override func layout() {
        super.layout()
        if needsSplitPositionUpdate {
            applyPreferredSplitPosition()
        }
    }

    func configureFolder(url: URL, inventory: FolderInventory) {
        let rows = FolderPreviewDisplay.sorted(inventory.entries).prefix(500).map(PreviewRow.init(entry:))
        let nodes = rows.map { FolderPreviewNode(row: $0) }
        let itemCount = inventory.isPartial ? "\(inventory.entries.count)+ items" : "\(inventory.entries.count) items"
        let subtitle = inventory.totalSize > 0
            ? "\(itemCount) · \(ByteCountFormatter.preview.string(fromByteCount: inventory.totalSize)) in shown files"
            : itemCount
        applyChrome(
            title: url.lastPathComponent,
            subtitle: subtitle,
            icon: NSWorkspace.shared.icon(for: .folder),
            badge: inventory.isPartial ? "Partial" : nil
        )
        contentMode = .outline
        folderRootCount = nodes.count
        filterControl.selectedSegment = FolderPreviewFilter.all.rawValue
        outlineDataSource.configure(rootNodes: nodes, filter: .all)
        setFilterBarVisible(true)
        showOutline(emptyMessage: "This folder is empty.")
    }

    func configureArchive(url: URL, entries: [ArchiveEntry]) {
        let rows = entries.prefix(500).map { PreviewRow(archiveEntry: $0) }
        applyChrome(
            title: url.lastPathComponent,
            subtitle: "\(entries.count) archive entries",
            icon: icon(for: url),
            badge: nil
        )
        setFilterBarVisible(false)
        showTable(rows: rows, emptyMessage: "This archive is empty.")
    }

    func configureLoading(url: URL, isDirectory: Bool) {
        applyChrome(
            title: url.lastPathComponent,
            subtitle: isDirectory ? "Loading folder contents..." : "Loading preview...",
            icon: isDirectory ? NSWorkspace.shared.icon(for: .folder) : icon(for: url),
            badge: nil
        )
        setFilterBarVisible(false)
        showTable(rows: [], emptyMessage: "Loading contents...")
    }

    func configureError(title: String, error: Error) {
        applyChrome(
            title: title,
            subtitle: "Could not create preview",
            icon: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) ?? NSImage(),
            badge: "Error"
        )
        setFilterBarVisible(false)
        showTable(rows: [], emptyMessage: error.localizedDescription)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        [header, filterBar, divider, splitView, emptyField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        setupHeader()
        setupFilterBar()
        setupTable()
        setupOutline()
        setupSplitView()
        setupEmptyState()
        setupSelectionCallbacks()

        divider.boxType = .separator
        let filterHeight = filterBar.heightAnchor.constraint(equalToConstant: 0)
        filterBarHeightConstraint = filterHeight

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 76),

            filterBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            filterBar.topAnchor.constraint(equalTo: header.bottomAnchor),
            filterHeight,

            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: filterBar.bottomAnchor),

            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyField.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyField.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyField.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, multiplier: 0.72)
        ])
    }

    private func setupHeader() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 20, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle

        summaryField.translatesAutoresizingMaskIntoConstraints = false
        summaryField.font = .systemFont(ofSize: 13, weight: .regular)
        summaryField.textColor = .secondaryLabelColor
        summaryField.lineBreakMode = .byTruncatingMiddle

        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        statusBadge.textColor = .secondaryLabelColor
        statusBadge.alignment = .center
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 8
        statusBadge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        statusBadge.isHidden = true

        [iconView, titleField, summaryField, statusBadge].forEach(header.addSubview)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 38),
            iconView.heightAnchor.constraint(equalToConstant: 38),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -12),
            titleField.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),

            summaryField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            summaryField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22),
            summaryField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 5),

            statusBadge.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22),
            statusBadge.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            statusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            statusBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func setupFilterBar() {
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.target = self
        filterControl.action = #selector(filterChanged(_:))
        filterControl.selectedSegment = FolderPreviewFilter.all.rawValue

        filterBar.addSubview(filterControl)

        NSLayoutConstraint.activate([
            filterControl.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor, constant: 22),
            filterControl.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            filterControl.widthAnchor.constraint(equalToConstant: 360)
        ])
    }

    private func setupTable() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        tableView.delegate = tableDataSource
        tableView.dataSource = tableDataSource
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 34
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.selectionHighlightStyle = .regular
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.backgroundColor = .windowBackgroundColor

        addColumns(to: tableView)
    }

    private func setupOutline() {
        outlineView.delegate = outlineDataSource
        outlineView.dataSource = outlineDataSource
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = 34
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true
        outlineView.selectionHighlightStyle = .regular
        outlineView.gridStyleMask = [.solidHorizontalGridLineMask]
        outlineView.backgroundColor = .windowBackgroundColor
        outlineView.indentationPerLevel = 18
        outlineView.autosaveExpandedItems = false

        addColumns(to: outlineView)
        outlineView.outlineTableColumn = outlineView.tableColumn(withIdentifier: PreviewColumn.name.identifier)
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(selectionPreviewPane)
        selectionPreviewPane.isHidden = true

        selectionPreviewPane.translatesAutoresizingMaskIntoConstraints = false
        selectionPreviewPane.setContentHuggingPriority(.required, for: .horizontal)
        selectionPreviewPane.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let width = selectionPreviewPane.widthAnchor.constraint(equalToConstant: 286)
        width.priority = .defaultHigh
        let minWidth = selectionPreviewPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        minWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([width, minWidth])
    }

    private func setupEmptyState() {
        emptyField.font = .systemFont(ofSize: 14, weight: .regular)
        emptyField.textColor = .secondaryLabelColor
        emptyField.alignment = .center
        emptyField.lineBreakMode = .byWordWrapping
        emptyField.maximumNumberOfLines = 3
        emptyField.isHidden = true
    }

    private func setupSelectionCallbacks() {
        tableDataSource.onSelectionChange = { [weak self] row in
            self?.showSelectionPreview(for: row)
        }
        outlineDataSource.onSelectionChange = { [weak self] row in
            self?.showSelectionPreview(for: row)
        }
    }

    private func applyChrome(
        title: String,
        subtitle: String,
        icon: NSImage,
        badge: String?
    ) {
        titleField.stringValue = title.isEmpty ? "Folder" : title
        summaryField.stringValue = subtitle
        iconView.image = icon

        statusBadge.stringValue = badge ?? ""
        statusBadge.isHidden = badge == nil
    }

    private func showTable(rows: [PreviewRow], emptyMessage: String) {
        contentMode = .table
        outlineDataSource.reset()
        scrollView.documentView = tableView

        tableDataSource.rows = rows
        tableView.reloadData()
        tableView.deselectAll(nil)
        showSelectionPreview(for: nil)

        emptyField.stringValue = emptyMessage
        emptyField.isHidden = !rows.isEmpty
        scrollView.isHidden = rows.isEmpty
    }

    private func showOutline(emptyMessage: String) {
        tableDataSource.rows = []
        tableView.reloadData()
        scrollView.documentView = outlineView
        outlineView.reloadData()
        outlineView.deselectAll(nil)
        showSelectionPreview(for: nil)
        updateOutlineEmptyState(emptyMessage: emptyMessage)
    }

    private func updateOutlineEmptyState(emptyMessage: String? = nil) {
        let visibleCount = outlineDataSource.visibleRootCount
        if folderRootCount == 0 {
            emptyField.stringValue = emptyMessage ?? "This folder is empty."
        } else {
            emptyField.stringValue = "No items match this filter."
        }
        emptyField.isHidden = visibleCount > 0
        scrollView.isHidden = visibleCount == 0
    }

    private func setFilterBarVisible(_ visible: Bool) {
        filterBar.isHidden = !visible
        filterBarHeightConstraint?.constant = visible ? 42 : 0
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        guard contentMode == .outline,
              let filter = FolderPreviewFilter(rawValue: sender.selectedSegment) else { return }
        outlineDataSource.filter = filter
        outlineView.reloadData()
        outlineView.deselectAll(nil)
        showSelectionPreview(for: nil)
        updateOutlineEmptyState()
    }

    private func showSelectionPreview(for row: PreviewRow?) {
        selectionPreviewTask?.cancel()
        let id = UUID()
        selectionPreviewID = id

        guard let row else {
            setSelectionPreviewVisible(false)
            selectionPreviewPane.configureIdle()
            return
        }

        setSelectionPreviewVisible(true)
        selectionPreviewPane.configure(row: row, image: icon(for: row))

        guard row.supportsThumbnail, let url = row.url else { return }
        let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        selectionPreviewTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                try Task.checkCancellation()
                let image = try await PreviewThumbnailGenerator.thumbnail(
                    for: url,
                    size: CGSize(width: 420, height: 280),
                    scale: scale
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self, self.selectionPreviewID == id else { return }
                    self.selectionPreviewPane.updateImage(image, representedPath: row.path)
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard let self, self.selectionPreviewID == id else { return }
                    self.selectionPreviewPane.keepFallbackImage(representedPath: row.path)
                }
            }
        }
    }

    private func setSelectionPreviewVisible(_ visible: Bool) {
        guard isSelectionPreviewVisible != visible else { return }
        isSelectionPreviewVisible = visible
        selectionPreviewPane.isHidden = !visible
        needsSplitPositionUpdate = visible
        splitView.adjustSubviews()
        needsLayout = true
    }

    private func applyPreferredSplitPosition() {
        guard isSelectionPreviewVisible else {
            needsSplitPositionUpdate = false
            return
        }

        let width = splitView.bounds.width
        guard width > 0 else { return }

        let preferredWidth = min(460, max(286, width * 0.3))
        splitView.setPosition(width - preferredWidth, ofDividerAt: 0)
        needsSplitPositionUpdate = false
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let width = splitView.bounds.width
        guard isSelectionPreviewVisible, width > 0 else { return width }
        let maxPaneWidth = min(520, max(286, width * 0.38))
        let minPaneWidth = min(260, width * 0.45)
        let minPosition = max(360, width - maxPaneWidth)
        let maxPosition = max(minPosition, width - minPaneWidth)
        return min(max(proposedPosition, minPosition), maxPosition)
    }

    private func addColumns(to tableView: NSTableView) {
        addColumn(to: tableView, id: .name, title: "Name", width: 360, minWidth: 180)
        addColumn(to: tableView, id: .kind, title: "Kind", width: 150, minWidth: 90)
        addColumn(to: tableView, id: .size, title: "Size", width: 110, minWidth: 76)
        addColumn(to: tableView, id: .modified, title: "Modified", width: 150, minWidth: 110)
    }

    private func addColumn(to tableView: NSTableView, id: PreviewColumn, title: String, width: CGFloat, minWidth: CGFloat) {
        let column = NSTableColumn(identifier: id.identifier)
        column.title = title
        column.width = width
        column.minWidth = minWidth
        tableView.addTableColumn(column)
    }

    private func icon(for url: URL) -> NSImage {
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
    }

    private func icon(for item: PreviewRow) -> NSImage {
        if item.isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }

        let ext = (item.name as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }

        return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
    }
}

private final class PreviewTableView: NSTableView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override var needsPanelToBecomeKey: Bool {
        false
    }
}

private final class PreviewOutlineView: NSOutlineView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override var needsPanelToBecomeKey: Bool {
        false
    }
}

private enum PreviewContentMode {
    case table, outline
}

private enum PreviewColumn: String {
    case name, kind, size, modified

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }
}

private struct PreviewRow {
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

private final class FolderPreviewNode {
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

private final class PreviewOutlineDataSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var filter: FolderPreviewFilter = .all
    var onSelectionChange: ((PreviewRow?) -> Void)?
    private var rootNodes: [FolderPreviewNode] = []
    private var iconsByKey: [String: NSImage] = [:]
    private var loadTasksByPath: [String: Task<Void, Never>] = [:]
    private var generation = 0

    var visibleRootCount: Int {
        children(of: nil).count
    }

    func configure(rootNodes: [FolderPreviewNode], filter: FolderPreviewFilter) {
        reset()
        self.rootNodes = rootNodes
        self.filter = filter
    }

    func reset() {
        loadTasksByPath.values.forEach { $0.cancel() }
        loadTasksByPath.removeAll()
        rootNodes = []
        iconsByKey.removeAll(keepingCapacity: true)
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
        return row.isDirectory
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
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
            cell.configure(text: row.name, icon: icon(for: row), path: row.path)
            return cell
        case .kind:
            return textCell(tableView: outlineView, text: row.kind)
        case .size:
            return textCell(
                tableView: outlineView,
                text: row.sizeText,
                alignment: .right
            )
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

    private func icon(for item: PreviewRow) -> NSImage {
        if item.isDirectory {
            return cachedIcon(key: "folder") {
                NSWorkspace.shared.icon(for: .folder)
            }
        }

        let ext = (item.name as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            return cachedIcon(key: "type:\(ext)") {
                NSWorkspace.shared.icon(for: type)
            }
        }

        return cachedIcon(key: "doc") {
            NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        }
    }

    private func cachedIcon(key: String, load: () -> NSImage) -> NSImage {
        if let image = iconsByKey[key] {
            return image
        }
        let image = load()
        iconsByKey[key] = image
        return image
    }
}

private final class PreviewTableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [PreviewRow] = []
    var onSelectionChange: ((PreviewRow?) -> Void)?
    private var iconsByKey: [String: NSImage] = [:]

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
            cell.configure(text: item.name, icon: icon(for: item), path: item.path)
            return cell
        case .kind:
            return textCell(tableView: tableView, text: item.kind)
        case .size:
            return textCell(
                tableView: tableView,
                text: item.sizeText,
                alignment: .right
            )
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

    private func icon(for item: PreviewRow) -> NSImage {
        if item.isDirectory {
            return cachedIcon(key: "folder") {
                NSWorkspace.shared.icon(for: .folder)
            }
        }

        let ext = (item.name as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            return cachedIcon(key: "type:\(ext)") {
                NSWorkspace.shared.icon(for: type)
            }
        }

        return cachedIcon(key: "doc") {
            NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        }
    }

    private func cachedIcon(key: String, load: () -> NSImage) -> NSImage {
        if let image = iconsByKey[key] {
            return image
        }
        let image = load()
        iconsByKey[key] = image
        return image
    }
}

private final class SelectionPreviewPane: NSView {
    private let stackView = NSStackView()
    private let previewBox = NSView()
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let kindField = NSTextField(labelWithString: "")
    private let sizeRow = PreviewMetadataRow(title: "Size")
    private let modifiedRow = PreviewMetadataRow(title: "Modified")
    private let pathRow = PreviewMetadataRow(title: "Path")
    private var representedPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        configureIdle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        configureIdle()
    }

    func configureIdle() {
        representedPath = nil
        imageView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        titleField.stringValue = "Select an item"
        kindField.stringValue = ""
        sizeRow.setValue("—")
        modifiedRow.setValue("—")
        pathRow.setValue("—")
    }

    func configure(row: PreviewRow, image: NSImage) {
        representedPath = row.path
        imageView.image = image
        titleField.stringValue = row.name
        kindField.stringValue = row.kind
        sizeRow.setValue(row.sizeText)
        modifiedRow.setValue(row.modifiedText)
        pathRow.setValue(row.path)
    }

    func updateImage(_ image: NSImage, representedPath path: String) {
        guard representedPath == path else { return }
        imageView.image = image
    }

    func keepFallbackImage(representedPath path: String) {
        guard representedPath == path else { return }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.36).cgColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 18, left: 16, bottom: 16, right: 16)

        previewBox.translatesAutoresizingMaskIntoConstraints = false
        previewBox.wantsLayer = true
        previewBox.layer?.cornerRadius = 8
        previewBox.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        previewBox.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        previewBox.layer?.borderWidth = 1

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown

        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.maximumNumberOfLines = 2

        kindField.font = .systemFont(ofSize: 12, weight: .regular)
        kindField.textColor = .secondaryLabelColor
        kindField.lineBreakMode = .byTruncatingMiddle

        previewBox.addSubview(imageView)
        [previewBox, titleField, kindField, sizeRow, modifiedRow, pathRow].forEach(stackView.addArrangedSubview)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            previewBox.heightAnchor.constraint(equalToConstant: 190),

            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: previewBox.leadingAnchor, constant: 14),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: previewBox.trailingAnchor, constant: -14),
            imageView.topAnchor.constraint(greaterThanOrEqualTo: previewBox.topAnchor, constant: 14),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: previewBox.bottomAnchor, constant: -14),
            imageView.centerXAnchor.constraint(equalTo: previewBox.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: previewBox.centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: previewBox.widthAnchor, constant: -28),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: previewBox.heightAnchor, constant: -28)
        ])
    }
}

private final class PreviewMetadataRow: NSView {
    private let labelField: NSTextField
    private let valueField = NSTextField(labelWithString: "")

    init(title: String) {
        labelField = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        labelField = NSTextField(labelWithString: "")
        super.init(coder: coder)
        setup()
    }

    func setValue(_ value: String) {
        valueField.stringValue = value
    }

    private func setup() {
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.font = .systemFont(ofSize: 11, weight: .medium)
        labelField.textColor = .tertiaryLabelColor

        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.font = .systemFont(ofSize: 12, weight: .regular)
        valueField.textColor = .secondaryLabelColor
        valueField.lineBreakMode = .byTruncatingMiddle

        [labelField, valueField].forEach(addSubview)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelField.topAnchor.constraint(equalTo: topAnchor),
            labelField.widthAnchor.constraint(equalToConstant: 62),
            labelField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            valueField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 10),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueField.topAnchor.constraint(equalTo: topAnchor),
            valueField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private enum PreviewThumbnailGenerator {
    static func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async throws -> NSImage {
        if let image = try await imageThumbnail(for: url, size: size, scale: scale) {
            return image
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    private static func imageThumbnail(for url: URL, size: CGSize, scale: CGFloat) async throws -> NSImage? {
        guard isImage(url) else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
                return nil
            }

            let maxPixelSize = max(Int(size.width * scale), Int(size.height * scale))
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return nil
            }

            return NSImage(
                cgImage: image,
                size: CGSize(
                    width: CGFloat(image.width) / scale,
                    height: CGFloat(image.height) / scale
                )
            )
        }.value
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

private final class NameCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("NameCellView")

    private let fileIconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    var representedPath: String?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        identifier = Self.identifier
        setup()
    }

    func configure(text: String, icon: NSImage, path: String) {
        representedPath = path
        titleField.stringValue = text
        setIcon(icon)
    }

    func setIcon(_ image: NSImage) {
        fileIconView.image = image
    }

    private func setup() {
        fileIconView.translatesAutoresizingMaskIntoConstraints = false
        fileIconView.imageScaling = .scaleProportionallyUpOrDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle

        [fileIconView, titleField].forEach(addSubview)

        NSLayoutConstraint.activate([
            fileIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            fileIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileIconView.widthAnchor.constraint(equalToConstant: 22),
            fileIconView.heightAnchor.constraint(equalToConstant: 22),

            titleField.leadingAnchor.constraint(equalTo: fileIconView.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class TextCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("TextCellView")

    private let valueField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        identifier = Self.identifier
        setup()
    }

    func configure(text: String, alignment: NSTextAlignment) {
        valueField.stringValue = text
        valueField.alignment = alignment
    }

    private func setup() {
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.font = .systemFont(ofSize: 13)
        valueField.textColor = .secondaryLabelColor
        valueField.lineBreakMode = .byTruncatingMiddle
        addSubview(valueField)

        NSLayoutConstraint.activate([
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private extension ByteCountFormatter {
    static let preview: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter
    }()
}

private extension DateFormatter {
    static let preview: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

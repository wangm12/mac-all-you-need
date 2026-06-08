import Core
import Platform
import SwiftUI

public struct FolderPreviewView: View {
    public enum Mode: String, CaseIterable, Identifiable {
        case files, grid, analyze
        public var id: String {
            rawValue
        }
    }

    @State private var inventory: FolderInventory?
    @State private var fileEntries: [FolderEntry] = []
    @State private var imageEntries: [FolderEntry] = []
    @State private var errorMessage: String?
    @State private var mode: Mode = .files
    @State private var currentURL: URL
    @State private var backStack: [URL] = []
    public let folderURL: URL
    public let onAction: ((PreviewAction) -> Void)?

    public init(folderURL: URL, onAction: ((PreviewAction) -> Void)? = nil) {
        self.folderURL = folderURL
        self.onAction = onAction
        _currentURL = State(initialValue: folderURL)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if let previous = backStack.popLast() { currentURL = previous }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 22, height: 22)
                }
                .disabled(backStack.isEmpty)
                .buttonStyle(.borderless)
                Image(systemName: "folder")
                    .foregroundStyle(FolderPreviewUI.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentURL.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let inv = inventory {
                        HStack(spacing: 6) {
                            Text("\(inv.entries.count) items")
                            Text(byteCountFormatter.string(fromByteCount: inv.totalSize))
                            if inv.isPartial {
                                FolderPreviewStatusBadge(text: "Partial", kind: .warning)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(FolderPreviewUI.secondary)
                    }
                }
                if let inv = inventory {
                    if inv.entries.isEmpty {
                        FolderPreviewStatusBadge(text: "Empty", kind: .neutral)
                    }
                }
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FolderPreviewUI.header)
            Divider()
            Group {
                if let inv = inventory {
                    if inv.entries.isEmpty {
                        FolderPreviewStateView(
                            symbol: "folder",
                            title: "Folder is empty",
                            message: currentURL.path
                        )
                    } else {
                        switch mode {
                        case .files:
                            FolderFilesView(entries: fileEntries, onAction: onAction) { url in
                                backStack.append(currentURL)
                                currentURL = url
                            }
                        case .grid:
                            FolderGridView(entries: imageEntries)
                        case .analyze:
                            FolderAnalyzeView(inventory: inv)
                        }
                    }
                } else if let errorMessage {
                    FolderPreviewStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Could not scan folder",
                        message: errorMessage,
                        kind: .error
                    )
                } else {
                    FolderPreviewStateView(
                        symbol: "folder.badge.gearshape",
                        title: "Scanning folder",
                        message: currentURL.path,
                        isLoading: true
                    )
                }
            }
            .background(FolderPreviewUI.background)
        }
        .background(FolderPreviewUI.background)
        .task(id: currentURL) {
            inventory = nil
            fileEntries = []
            imageEntries = []
            errorMessage = nil
            let maxEntries = AppGroupSettings.defaults.integer(forKey: "folderPreviewMaxEntries")
            let includeHidden = AppGroupSettings.defaults.bool(forKey: "folderPreviewIncludeHidden")
            let cascade = FolderPreviewSettings.cascadeEnabled()
            do {
                let inv = try await FolderPreviewListing.enumerate(
                    url: currentURL,
                    maxEntries: maxEntries == 0 ? 50000 : maxEntries,
                    includeHidden: includeHidden,
                    cascade: cascade
                )
                let sorted = await Task.detached(priority: .userInitiated) {
                    FolderPreviewDisplay.sorted(inv.entries)
                }.value
                try Task.checkCancellation()
                fileEntries = sorted
                imageEntries = sorted.filter { $0.kind == .images }
                inventory = inv
                if let inv = inventory, autoSuggestGrid(inv) { mode = .grid }
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func autoSuggestGrid(_ inv: FolderInventory) -> Bool {
        let imageCount = inv.breakdown[.images, default: 0]
        let nonFolderCount = inv.entries.filter { !$0.isDirectory }.count
        return nonFolderCount > 10 && Double(imageCount) / Double(nonFolderCount) >= 0.4
    }
}

enum FolderPreviewUI {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let header = Color(nsColor: .controlBackgroundColor)
    static let panel = Color(nsColor: .textBackgroundColor)
    static let fill = Color.primary.opacity(0.055)
    static let hover = Color.primary.opacity(0.045)
    static let border = Color.primary.opacity(0.10)
    static let strongBorder = Color.primary.opacity(0.18)
    static let secondary = Color.secondary
    static let muted = Color.secondary.opacity(0.65)
    static let warning = Color.orange.opacity(0.78)
    static let danger = Color.red.opacity(0.78)
}

struct FolderPreviewStateView: View {
    let symbol: String
    let title: String
    let message: String?
    var kind: Kind = .neutral
    var isLoading = false

    enum Kind {
        case neutral, error
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FolderPreviewUI.fill)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(kind == .error ? FolderPreviewUI.danger : FolderPreviewUI.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FolderPreviewUI.border, lineWidth: 1)
            )

            Text(title)
                .font(.system(size: 14, weight: .semibold))
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(FolderPreviewUI.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 440)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct FolderPreviewStatusBadge: View {
    let text: String
    var kind: Kind = .neutral

    enum Kind {
        case neutral, warning
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
    }

    private var color: Color {
        switch kind {
        case .neutral: FolderPreviewUI.secondary
        case .warning: FolderPreviewUI.warning
        }
    }
}

public enum PreviewAction: Sendable {
    case open(URL)
    case copy(URL)
    case revealInFinder(URL)
}

private let byteCountFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    f.countStyle = .file
    return f
}()

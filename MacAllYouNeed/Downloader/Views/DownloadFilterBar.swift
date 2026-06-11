import Core
import SwiftUI

// MARK: - Surface

enum DownloadsListSurface {
    case main
    case commandCenter
}

// MARK: - Filter

enum DownloadsListFilter {
    case all
    case activeQueue
    case completed

    func includes(_ state: DownloadState) -> Bool {
        switch self {
        case .all:
            true
        case .activeQueue:
            switch state {
            case .queued, .running, .paused, .failed:
                true
            case .completed:
                false
            }
        case .completed:
            state == .completed
        }
    }
}

// MARK: - Queue presentation

enum DownloadsQueuePresentation {
    static func visibleRows(_ rows: [DownloadRecord], filter: DownloadsListFilter) -> [DownloadRecord] {
        rows.filter { filter.includes($0.state) }
    }

    static func showsFailedBanner(rows: [DownloadRecord], filter: DownloadsListFilter) -> Bool {
        guard filter != .completed else { return false }
        return visibleRows(rows, filter: filter).contains { $0.state == .failed }
    }

    static func headerActionTitle(rows: [DownloadRecord], filter: DownloadsListFilter) -> String? {
        switch filter {
        case .activeQueue, .all:
            showsFailedBanner(rows: rows, filter: filter) ? "Retry Failed" : nil
        case .completed:
            visibleRows(rows, filter: filter).isEmpty ? nil : "Open Folder"
        }
    }
}

// MARK: - Empty state

struct DownloadsEmptyStateModel: Equatable {
    let title: String
    let subtitle: String
    let secondaryActionTitle: String?
    let primaryActionTitle: String?
}

enum DownloadsEmptyStatePresentation {
    static func model(for filter: DownloadsListFilter) -> DownloadsEmptyStateModel {
        switch filter {
        case .all, .activeQueue:
            DownloadsEmptyStateModel(
                title: "No downloads queued",
                subtitle: "Add a URL, paste with ⌘V, or send a link from the optional Mac All You Need Companion.",
                secondaryActionTitle: "Paste URL",
                primaryActionTitle: "Add URL"
            )
        case .completed:
            DownloadsEmptyStateModel(
                title: "No completed downloads",
                subtitle: "Finished media will appear here with quick access to its folder.",
                secondaryActionTitle: nil,
                primaryActionTitle: nil
            )
        }
    }
}

// MARK: - Empty state view

struct DownloadsEmptyStateView: View {
    let model: DownloadsEmptyStateModel
    let onPasteURL: () -> Void
    let onAddURL: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(model.title)
                    .font(.callout.weight(.semibold))
                Text(model.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.secondaryActionTitle != nil || model.primaryActionTitle != nil {
                HStack(spacing: 8) {
                    if let secondaryTitle = model.secondaryActionTitle {
                        MAYNButton(secondaryTitle, action: onPasteURL)
                    }
                    if let primaryTitle = model.primaryActionTitle {
                        MAYNButton(primaryTitle, role: .primary, action: onAddURL)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

# SwiftUI handoff notes

## View hierarchy

```swift
FunctionPageShell(
    title: "Downloads",
    subtitle: "Queue media downloads, review results, and tune downloader behavior.",
    tabs: DownloadTab.allCases,
    selection: $selectedTab
) {
    MAYNButton("Paste URL") { viewModel.enqueueClipboardURL() }
    MAYNButton("Add URL", role: .primary) { showingAddURL = true }
} content: {
    FunctionPageScrollContent {
        switch selectedTab {
        case .queue: DownloadsQueueContent(viewModel: viewModel)
        case .completed: DownloadsCompletedContent(viewModel: viewModel)
        case .settings: DownloadsSettingsContent(viewModel: viewModel)
        }
    }
}
```

## Domain component

`DownloadJobRow` is the one new component proposed by this pack. It should live near `DownloadsListView` unless the team wants a `MAYNDownloadsUI.swift` sibling. It should not introduce new tokens.

Required inputs:

```swift
struct DownloadJobRowModel: Identifiable {
    var id: RecordID
    var title: String
    var subtitle: String        // uploader + duration
    var thumbnail: NSImage?
    var state: DownloadState
    var phase: String
    var progress: Double
    var speedText: String?
    var etaText: String?
    var lastError: String?
    var destinationPath: String?
}
```

Status mapping:

```swift
extension DownloadState {
    var pillKind: StatusPill.Kind {
        switch self {
        case .completed: return .success
        case .failed: return .danger
        case .paused: return .warning
        case .running: return .progress
        default: return .neutral
        }
    }
}
```

## Settings tab

Use `MAYNSection`, `MAYNSettingsRow`, `MAYNDivider`, `MAYNNumericStepper`, `MAYNDropdown`, and `MAYNButton`. Do not use raw `Picker(...).pickerStyle(.segmented)`.

## Add URL

Use a sheet with `MAYNTextField` for single URL input. If multi-line URL paste is required, add a tokenized `MAYNMultilineTextField` primitive rather than styling `TextEditor` inline.

## Reduce Motion

Progress changes may animate opacity/fill via `MAYNMotion.controlAnimation(reduceMotion:)`. Row insertion/removal should use the existing page/content transition helpers and collapse offsets when Reduce Motion is enabled.
```

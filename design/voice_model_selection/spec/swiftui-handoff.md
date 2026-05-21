# SwiftUI handoff - Advanced engine picker

## Component shape

```swift
struct VoiceEnginePickerSheet: View {
    @State private var selectedEngineID: Engine.ID
    @State private var filter: EngineFilter = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            PickerHeader(title: "Choose recognition engine", subtitle: "Advanced selection for exact local, cloud, and experimental recognizers.")

            HStack(spacing: 0) {
                EngineListPane(
                    engines: filteredEngines,
                    selectedEngineID: $selectedEngineID
                )
                .frame(width: 326)

                MAYNDivider(.vertical)

                EngineDetailPane(engine: selectedEngine)
                    .frame(width: 334)
            }

            FooterNote("Rows only identify engines. Status and actions live in the detail pane.")
        }
        .frame(width: 820, height: 660)
        .background(MAYNTheme.panel)
    }
}
```

## Rules

- Do not show `Selected`, `Not installed`, `Needs API key`, or `Unavailable` both in the row and in the detail pane.
- Rows should not include `Use`, `Configure`, `Download`, or `Delete` buttons.
- Use exactly one primary action in the detail pane.
- Put destructive local-file actions as secondary actions in the detail pane only.
- Keep experimental/unavailable engines in this picker, not on the main Models page.

## Row content

Each row should contain:

- icon: local/cloud/experimental
- title
- one short description
- optional checkmark for the current engine

No status pill unless the row is unavailable and cannot be selected; even then prefer dimming over another pill.

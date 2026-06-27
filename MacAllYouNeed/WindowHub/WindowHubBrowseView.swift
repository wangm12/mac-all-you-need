import SwiftUI

struct WindowHubBrowseView: View {
    @Bindable var coordinator: WindowHubCoordinator
    @State private var selectedAppID: String?
    @State private var selectedWindowID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WindowHubColumnView(
                title: "Apps",
                items: coordinator.snapshot.sections.map { ($0.id, $0.appName) },
                selection: selectedAppID
            ) { id in
                selectedAppID = id
                selectedWindowID = nil
            }
            WindowHubColumnView(
                title: "Windows",
                items: selectedSection?.windowGroups.map { ($0.id, $0.title) } ?? [],
                selection: selectedWindowID
            ) { id in
                selectedWindowID = id
            }
            VStack(alignment: .leading) {
                Text("Targets")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(selectedGroup?.visibleTargets ?? [], id: \.id) { target in
                            WindowHubTargetRowView(
                                target: target,
                                isSelected: coordinator.selectedTargetID == target.id,
                                onActivate: {
                                    Task { await coordinator.activate(target: target) }
                                },
                                onSelect: {
                                    coordinator.selectTarget(target)
                                },
                                onAction: { action in
                                    coordinator.requestDirectAction(action, target: target)
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedSection: WindowHubAppSection? {
        coordinator.snapshot.sections.first { $0.id == selectedAppID }
            ?? coordinator.snapshot.sections.first
    }

    private var selectedGroup: WindowHubWindowGroup? {
        selectedSection?.windowGroups.first { $0.id == selectedWindowID }
            ?? selectedSection?.windowGroups.first
    }
}

struct WindowHubColumnView: View {
    let title: String
    let items: [(String, String)]
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.0) { id, label in
                        Button(label) { onSelect(id) }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == id ? MAYNTheme.selected : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .frame(width: 180)
    }
}

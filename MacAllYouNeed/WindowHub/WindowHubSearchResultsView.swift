import SwiftUI

struct WindowHubSearchResultsView: View {
    @Bindable var coordinator: WindowHubCoordinator

    var body: some View {
        ScrollView {
            if coordinator.filteredTargets.isEmpty {
                ContentUnavailableView(
                    "No match",
                    systemImage: "magnifyingglass",
                    description: Text("Try an app name, window title, or tab title.")
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(coordinator.filteredTargets, id: \.id) { target in
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }
}

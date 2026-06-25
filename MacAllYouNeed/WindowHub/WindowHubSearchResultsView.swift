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
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(coordinator.filteredTargets, id: \.id) { target in
                        WindowHubTargetRowView(target: target) {
                            Task { await coordinator.activate(target: target) }
                        } onAction: { action in
                            coordinator.requestDirectAction(action, target: target)
                        }
                        Text(target.breadcrumb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }
            }
        }
    }
}

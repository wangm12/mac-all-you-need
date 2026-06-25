import SwiftUI

struct WindowHubOverlayView: View {
    @Bindable var coordinator: WindowHubCoordinator
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 0) {
                toolbar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                if !coordinator.isAccessibilityGranted {
                    accessibilityBanner
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                } else if let failureMessage = indexingFailureMessage {
                    failedBanner(failureMessage)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                Divider().overlay(MAYNTheme.subtleBorder)
                content
            }

            if coordinator.isAIOrganizing {
                aiOrganizingOverlay
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            searchFocused = true
        }
        .sheet(isPresented: actionConfirmationBinding) {
            if let plan = coordinator.pendingPlan {
                WindowHubActionConfirmationView(plan: plan) {
                    Task { await coordinator.confirmPendingPlan() }
                } onCancel: {
                    coordinator.dismissPendingPlan()
                }
            }
        }
        .sheet(isPresented: aiOrganizeBinding) {
            WindowHubAIOrganizeSheetView(coordinator: coordinator)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .foregroundStyle(MAYNTheme.progress)
            TextField("Search apps, windows, tabs…", text: Binding(
                get: { coordinator.searchQuery },
                set: { coordinator.updateSearchQuery($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            if coordinator.isIndexing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading tabs…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await coordinator.requestAIOrganize() }
            } label: {
                if coordinator.isAIOrganizing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("AI Organize", systemImage: "sparkles")
                }
            }
            .disabled(coordinator.isAIOrganizing)
            Button("Browse all apps…") { coordinator.showBrowseColumns() }
        }
    }

    private var accessibilityBanner: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
            Text("Accessibility permission is required to list and switch windows.")
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .font(.caption)
        .padding(10)
        .background(MAYNTheme.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var indexingFailureMessage: String? {
        if case .failed(let message) = coordinator.snapshot.phase {
            return message
        }
        return nil
    }

    private func failedBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
            Spacer()
        }
        .font(.caption)
        .padding(10)
        .background(MAYNTheme.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var aiOrganizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 10) {
                ProgressView()
                Text("Analyzing tabs…")
                    .font(.subheadline.weight(.medium))
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.mode {
        case .dashboard, .actionConfirmation:
            WindowHubMasonryDashboardView(coordinator: coordinator)
        case .searchResults:
            WindowHubSearchResultsView(coordinator: coordinator)
        case .browseColumns:
            WindowHubBrowseView(coordinator: coordinator)
        }
    }

    private var actionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { coordinator.mode == .actionConfirmation && !coordinator.isAIOrganizePresented },
            set: { if !$0 { coordinator.dismissPendingPlan() } }
        )
    }

    private var aiOrganizeBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isAIOrganizePresented },
            set: { if !$0 { coordinator.dismissAIOrganize() } }
        )
    }
}

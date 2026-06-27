import SwiftUI

struct WindowHubOverlayView: View {
    @Bindable var coordinator: WindowHubCoordinator
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isShellVisible = false

    private static let shellRadius: CGFloat = 28

    var body: some View {
        ZStack {
            shellBackdrop

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
                Divider().overlay(MAYNTheme.hairline)
                content
            }

            if coordinator.isAIOrganizing {
                aiOrganizingOverlay
            }
        }
        .clipShape(shellShape)
        .overlay {
            shellShape.stroke(MAYNTheme.hairline, lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.68 : 0.24),
            radius: colorScheme == .dark ? 45 : 40,
            y: colorScheme == .dark ? 30 : 28
        )
        .scaleEffect(isShellVisible ? 1 : 0.96)
        .opacity(isShellVisible ? 1 : 0)
        .offset(y: isShellVisible ? 0 : -6)
        .frame(minWidth: 720, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            coordinator.syncSelectionToNavigableTargets()
            withAnimation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion)) {
                isShellVisible = true
            }
            searchFocused = true
        }
        .onKeyPress(.upArrow) {
            coordinator.moveSelection(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            coordinator.moveSelection(delta: 1)
            return .handled
        }
        .onKeyPress(.return) {
            Task { await coordinator.activateSelectedTarget() }
            return .handled
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

    private var shellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.shellRadius, style: .continuous)
    }

    @ViewBuilder
    private var shellBackdrop: some View {
        if reduceTransparency {
            shellShape.fill(MAYNTheme.contentPanelElevated(colorScheme))
        } else if #available(macOS 26.0, *) {
            shellShape.fill(Color.clear)
                .glassEffect(.regular, in: shellShape)
        } else {
            shellShape.fill(.ultraThinMaterial)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .foregroundStyle(.secondary)
            TextField("Search apps, windows, tabs…", text: Binding(
                get: { coordinator.searchQuery },
                set: { coordinator.updateSearchQuery($0) }
            ))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MAYNTheme.panelSubtle, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(searchFocused ? MAYNTheme.focusRing : MAYNTheme.hairline, lineWidth: searchFocused ? 2 : 1)
            )
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
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(coordinator.isAIOrganizing)
            Button("Browse all apps…") { coordinator.showBrowseColumns() }
                .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(10)
        .background(MAYNTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MAYNTheme.hairline, lineWidth: 1)
        )
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
        .background(MAYNTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MAYNTheme.hairline, lineWidth: 1)
        )
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
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MAYNTheme.contentPanelElevated(colorScheme))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MAYNTheme.hairline, lineWidth: 1)
            }
        }
        .clipShape(shellShape)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.mode {
        case .dashboard, .actionConfirmation:
            WindowHubGroupedDashboardView(coordinator: coordinator)
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

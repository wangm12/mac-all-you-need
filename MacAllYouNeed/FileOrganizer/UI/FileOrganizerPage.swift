import AppKit
import Core
import SwiftUI

struct FileOrganizerPage: View {
    /// Injected composition root. The page owns no business logic.
    let coordinator: FileOrganizerCoordinator?

    @State private var isScanning = false
    @State private var currentProposal: OrganizationProposal?
    @State private var showingDiffPane = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            MAYNDivider()
            content
            Spacer()
        }
        .background(MAYNTheme.window)
        .sheet(isPresented: $showingDiffPane) {
            if let binding = Binding($currentProposal) {
                OrganizerDiffPane(proposal: binding) {
                    showingDiffPane = false
                    applyProposal()
                } onCancel: {
                    showingDiffPane = false
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            MAYNButton(role: .primary, action: scanDownloads) {
                Label("Scan Downloads", systemImage: "folder.badge.questionmark")
            }
            .disabled(isScanning)
            MAYNButton(role: .secondary, action: scanCustom) {
                Label("Scan Folder…", systemImage: "folder")
            }
            .disabled(isScanning)
            Spacer()
            if isScanning { ProgressView().scaleEffect(0.7) }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let error = errorMessage {
            Text(error)
                .foregroundStyle(MAYNTheme.danger)
                .font(.callout)
                .padding(16)
        } else if let proposal = currentProposal {
            VStack(spacing: 12) {
                Text("\(proposal.operations.count) operations proposed")
                    .foregroundStyle(.secondary)
                MAYNButton(role: .primary) { showingDiffPane = true } label: {
                    Text("Review Changes")
                }
            }
            .padding(16)
        } else {
            Text("No recent proposals. Scan a folder to organize files.")
                .foregroundStyle(.secondary)
                .padding(16)
        }
    }

    // MARK: - Actions

    private func scanDownloads() {
        guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        scan(url: url)
    }

    private func scanCustom() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            scan(url: url)
        }
    }

    private func scan(url: URL) {
        guard let coordinator else { return }
        errorMessage = nil
        isScanning = true
        Task { @MainActor in
            let proposal = await coordinator.scan(url: url)
            isScanning = false
            currentProposal = proposal
            if proposal == nil {
                errorMessage = "Could not read \(url.lastPathComponent)."
            }
        }
    }

    private func applyProposal() {
        guard let coordinator, let proposal = currentProposal else { return }
        do {
            try coordinator.apply(proposal: proposal)
            currentProposal = nil
        } catch {
            errorMessage = "Some changes failed: \(error.localizedDescription)"
        }
    }
}

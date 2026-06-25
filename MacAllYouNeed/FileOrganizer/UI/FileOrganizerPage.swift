import AppKit
import Core
import SwiftUI

struct FileOrganizerPage: View {
    let coordinator: FileOrganizerCoordinator?
    let controller: AppController?

    @State private var isScanning = false
    @State private var currentProposal: OrganizationProposal?
    @State private var showingDiffPane = false
    @State private var isShowingModelPicker = false
    @State private var errorMessage: String?
    @State private var settings = AIFileOrganizerSettings.load()

    private var modelSummary: String {
        let provider = settings.provider.label
        let model = settings.model.isEmpty ? settings.provider.defaultModel : settings.model
        return "\(provider) · \(model)"
    }

    var body: some View {
        MAYNSettingsPage(title: "AI File Organizer", subtitle: "Rename and re-file messy folders using on-device content extraction.") {
                MAYNSection(title: "Overview") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("One folder at a time")
                            .font(.headline.weight(.semibold))
                        Text("Scan a folder, review the proposed renames and moves, then apply only the changes you want. Configure the AI provider first for the smoothest setup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Scan actions
                MAYNSection(title: "Organize") {
                    MAYNSettingsRow(
                        title: "Scan a folder",
                        subtitle: "Analyze up to 50 files, propose clean names and subfolders, then review before any changes are made."
                    ) {
                        HStack(spacing: 8) {
                            MAYNButton("Downloads", role: .primary, action: scanDownloads)
                                .disabled(isScanning || coordinator == nil)
                            MAYNButton("Choose…", role: .secondary, action: scanCustom)
                                .disabled(isScanning || coordinator == nil)
                            if isScanning {
                                ProgressView().scaleEffect(0.75)
                            }
                        }
                    }

                    if coordinator == nil {
                        MAYNDivider()
                        MAYNSettingsRow(
                            title: "LLM not configured",
                            subtitle: "Configure an AI provider in Voice → Recognition → AI Cleanup to enable the organizer."
                        ) {
                            MAYNButton("Open Voice", role: .secondary) {
                                controller?.showMainWindow(destination: .voice)
                            }
                        }
                    }
                }

                // Error
                if let error = errorMessage {
                    MAYNSection(title: "Error") {
                        MAYNSettingsRow(title: error, subtitle: "") {
                            MAYNButton("Dismiss", role: .secondary) { errorMessage = nil }
                        }
                    }
                }

                // Proposed operations — show inline list
                if let proposal = currentProposal {
                    MAYNSection(title: "\(proposal.operations.count) Proposed Changes") {
                        ForEach(Array(proposal.operations.prefix(20).enumerated()), id: \.element.id) { index, op in
                            if index > 0 { MAYNDivider() }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(op.sourceURL.lastPathComponent)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(op.proposedFilename)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                if let sub = op.proposedSubfolder {
                                    Text("Subfolder: \(sub)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        if proposal.operations.count > 20 {
                            MAYNDivider()
                            MAYNSettingsRow(
                                title: "+\(proposal.operations.count - 20) more in review sheet",
                                subtitle: ""
                            ) { EmptyView() }
                        }
                    }
                    MAYNSection(title: "") {
                        HStack(spacing: 10) {
                            MAYNButton("Review & Apply…", role: .primary) { showingDiffPane = true }
                            MAYNButton("Discard", role: .secondary) { currentProposal = nil }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    MAYNSection(title: "Proposed Changes") {
                        MAYNSettingsRow(
                            title: "Nothing to review yet",
                            subtitle: "Choose a folder to generate a proposal. The review sheet shows the full rename and move plan before anything is applied."
                        ) {
                            EmptyView()
                        }
                    }
                }

                // Model info
                MAYNSection(title: "Model") {
                    MAYNSettingsRow(
                        title: "LLM provider",
                        subtitle: modelSummary
                    ) {
                        MAYNButton("Configure…", role: .secondary) {
                            isShowingModelPicker = true
                        }
                    }
                }

                // Naming Rules
                MAYNSection(title: "Naming Rules") {
                    MAYNSettingsRow(title: "Case style", subtitle: "How file names are capitalized.") {
                        MAYNDropdown(
                            selection: Binding(
                                get: { settings.namingCaseStyle },
                                set: { settings.namingCaseStyle = $0; AIFileOrganizerSettings.save(settings) }
                            ),
                            options: CaseStyle.allCases,
                            title: { $0.displayName }
                        )
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Max filename length", subtitle: "Characters (excluding extension).") {
                        MAYNNumericStepper(
                            text: "\(settings.maxFilenameLength)",
                            value: Binding(
                                get: { settings.maxFilenameLength },
                                set: { settings.maxFilenameLength = $0; AIFileOrganizerSettings.save(settings) }
                            ),
                            range: 20...200,
                            step: 10,
                            presets: [40, 60, 80, 100],
                            suffix: "chars",
                            fieldWidth: 60
                        )
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Max subfolder depth", subtitle: "0 = no subfolders.") {
                        MAYNNumericStepper(
                            text: "\(settings.maxSubfolderDepth)",
                            value: Binding(
                                get: { settings.maxSubfolderDepth },
                                set: { settings.maxSubfolderDepth = $0; AIFileOrganizerSettings.save(settings) }
                            ),
                            range: 0...4,
                            step: 1,
                            presets: [0, 1, 2, 3],
                            suffix: "levels",
                            fieldWidth: 60
                        )
                    }
                }

                // Watch Folders
                MAYNSection(title: "Watch Folders") {
                    MAYNSettingsRow(
                        title: "Auto-scan trigger",
                        subtitle: "When a new file appears in a watched folder, a notification prompts you to organize it."
                    ) {
                        MAYNButton("Add Folder…", role: .secondary) { addWatchFolder() }
                    }
                    ForEach(settings.watchedFolderPaths, id: \.self) { path in
                        MAYNDivider()
                        HStack {
                            Image(systemName: "folder.badge.plus").foregroundStyle(.secondary)
                            Text((path as NSString).lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            MAYNButton("Remove", role: .secondary) {
                                settings.watchedFolderPaths.removeAll { $0 == path }
                                AIFileOrganizerSettings.save(settings)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
        }
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
        .sheet(isPresented: $isShowingModelPicker) {
            if let controller {
                AIFileOrganizerModelPickerSheet(
                    controller: controller,
                    settings: $settings,
                    onClose: { isShowingModelPicker = false }
                )
            }
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
        currentProposal = nil
        isScanning = true
        Task { @MainActor in
            let proposal = await coordinator.scan(url: url)
            isScanning = false
            currentProposal = proposal
            if proposal == nil {
                errorMessage = "Could not read folder. Check Full Disk Access permission."
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

    private func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to watch for new files."
        if panel.runModal() == .OK, let url = panel.url {
            if !settings.watchedFolderPaths.contains(url.path) {
                settings.watchedFolderPaths.append(url.path)
                AIFileOrganizerSettings.save(settings)
            }
        }
    }
}

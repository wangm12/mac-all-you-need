import AppKit
import Core
import FluidAudio
import SwiftUI

struct VoiceAppProfilesSection: View {
    let controller: AppController
    @Binding var errorMessage: String?
    @State private var appProfiles: [VoiceAppProfile]
    @State private var profileEnabled = true
    @State private var profileBundleID = ""
    @State private var profileDisplayName = ""
    @State private var selectedRunningAppBundleID = ""
    @State private var runningAppOptions = VoiceProfileRunningAppOption.available()
    @State private var profilePrompt = ""
    @State private var profileLanguageRaw = "inherit"
    @State private var profileASRModelRaw = VoiceProfileASRModelSelection.inherit
    @State private var profileAutoSubmitKey: VoiceAutoSubmitKey = .none
    @State private var modelDownloadStatus: String?
    @State private var modelDownloadFraction: Double?
    @State private var downloadingModelID: VoiceASRModelID?

    init(controller: AppController, errorMessage: Binding<String?>) {
        self.controller = controller
        _errorMessage = errorMessage
        _appProfiles = State(initialValue: controller.listVoiceAppProfiles())
    }

    var body: some View {
        Group {
            MAYNSection(
                title: "Profiles",
                subtitle: VoiceAppProfileEditorPresentation.sectionSubtitle
            ) {
                if appProfiles.isEmpty {
                    MAYNSettingsRow(
                        title: "No profiles yet",
                        subtitle: "Create one for Cursor, Messages, browser text fields, or any app with different cleanup needs."
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(appProfiles.enumerated()), id: \.element.id) { offset, profile in
                        profileRow(profile)
                        if offset != appProfiles.count - 1 {
                            MAYNDivider()
                        }
                    }
                }
            }

            MAYNSection(
                title: "Profile editor",
                subtitle: "Pick the target app, then choose only the overrides that differ from global Voice settings."
            ) {
                MAYNSettingsRow(
                    title: "Enabled",
                    subtitle: "Saved profile becomes active immediately."
                ) {
                    Toggle("", isOn: $profileEnabled)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Target app",
                    subtitle: "Choose a running app. The bundle identifier is saved behind the scenes.",
                    minHeight: selectedTargetSubtitle == nil ? 54 : 72
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            MAYNDropdown(
                                selection: $selectedRunningAppBundleID,
                                options: runningAppPickerOptions,
                                title: runningAppTitle,
                                width: MAYNControlMetrics.widePickerWidth
                            )

                            MAYNButton(role: .secondary, height: MAYNControlMetrics.controlHeight, action: {
                                runningAppOptions = VoiceProfileRunningAppOption.available()
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }

                        if let selectedTargetSubtitle {
                            Text(selectedTargetSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Recognition model",
                    subtitle: VoiceAppProfileEditorPresentation.modelSubtitle,
                    minHeight: profileModelRowMinHeight
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        MAYNDropdown(
                            selection: $profileASRModelRaw,
                            options: VoiceAppProfileEditorPresentation.modelOptions,
                            title: VoiceAppProfileEditorPresentation.modelTitle,
                            width: MAYNControlMetrics.widePickerWidth
                        )

                        if let modelDownloadFraction {
                            ProgressView(value: modelDownloadFraction)
                                .frame(width: 170)
                        }

                        if let modelDownloadStatus {
                            Text(modelDownloadStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Language") {
                    MAYNDropdown(
                        selection: $profileLanguageRaw,
                        options: profileLanguageOptions,
                        title: profileLanguageTitle
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Auto-submit") {
                    MAYNDropdown(
                        selection: $profileAutoSubmitKey,
                        options: Array(VoiceAutoSubmitKey.allCases),
                        title: { autoSubmitLabel(for: $0) }
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Custom prompt",
                    subtitle: "Optional cleanup instructions applied for this app.",
                    minHeight: 92
                ) {
                    TextEditor(text: $profilePrompt)
                        .font(.callout)
                        .frame(width: MAYNControlMetrics.wideTextFieldWidth, height: 70)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2))
                        }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Profile action") {
                    MAYNButton("Save", role: .primary) { saveAppProfile() }
                        .disabled(profileBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: profileASRModelRaw) { _, _ in
                handleProfileASRModelSelectionChanged()
            }
            .onChange(of: selectedRunningAppBundleID) { _, bundleID in
                selectRunningApp(bundleID: bundleID)
            }
        }
    }

    private func profileRow(_ profile: VoiceAppProfile) -> some View {
        MAYNSettingsRow(
            title: profile.displayName,
            subtitle: profile.bundleID,
            minHeight: 54
        ) {
            HStack(spacing: 10) {
                StatusPill(text: profile.config.isEnabled ? "Enabled" : "Disabled", kind: profile.config.isEnabled ? .success : .neutral)
                StatusPill(text: profileModelLabel(profile.config.asrEngineID), kind: .neutral)
                StatusPill(text: autoSubmitLabel(for: profile.config.autoSubmitKey), kind: .neutral)
                MAYNButton(role: .destructive, height: HotkeyChipPresentation.compactHeight, action: {
                    deleteAppProfile(profile)
                }) {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private var selectedASRModelID: VoiceASRModelID? {
        VoiceASRModelID(storedIdentifier: profileASRModelRaw)
    }

    private var profileModelRowMinHeight: CGFloat {
        if modelDownloadFraction != nil { return 84 }
        if modelDownloadStatus != nil { return 72 }
        return 58
    }

    private var selectedTargetSubtitle: String? {
        guard !profileBundleID.isEmpty else { return nil }
        return "\(profileDisplayName.isEmpty ? profileBundleID : profileDisplayName) · \(profileBundleID)"
    }

    private var selectedModelStatusMessage: String? {
        guard let selectedASRModelID else { return nil }
        return isDownloaded(selectedASRModelID) ? "Model is available locally." : "Download before this model can be used reliably."
    }

    private func handleProfileASRModelSelectionChanged() {
        modelDownloadStatus = selectedModelStatusMessage
        guard let modelID = selectedASRModelID else {
            modelDownloadFraction = nil
            return
        }

        if downloadingModelID == modelID {
            return
        }

        modelDownloadFraction = nil
        guard !isDownloaded(modelID) else { return }
        downloadModel(modelID)
    }

    private func isDownloaded(_ modelID: VoiceASRModelID) -> Bool {
        guard #available(macOS 15, *) else { return false }
        return Qwen3AsrModels.modelsExist(
            at: Qwen3AsrModels.defaultCacheDirectory(variant: modelID.variant)
        )
    }

    private func downloadModel(_ modelID: VoiceASRModelID) {
        guard downloadingModelID == nil else { return }
        guard #available(macOS 15, *) else {
            modelDownloadStatus = "Requires macOS 15 or later."
            return
        }

        downloadingModelID = modelID
        modelDownloadFraction = 0
        modelDownloadStatus = "Preparing download..."
        Task {
            do {
                try await Qwen3AsrModels.download(
                    variant: modelID.variant,
                    progressHandler: { progress in
                        Task { @MainActor in
                            modelDownloadStatus = VoiceModelDownloadPresenter.describe(progress)
                            modelDownloadFraction = progress.fractionCompleted
                        }
                    }
                )
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFraction = nil
                    modelDownloadStatus = "Downloaded."
                }
            } catch {
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFraction = nil
                    modelDownloadStatus = error.localizedDescription
                }
            }
        }
    }

    private func saveAppProfile() {
        do {
            let bundleID = profileBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            try controller.upsertVoiceAppProfile(
                bundleID: bundleID,
                displayName: displayName.isEmpty ? bundleID : displayName,
                config: VoiceAppProfileConfig(
                    isEnabled: profileEnabled,
                    customPrompt: profilePrompt,
                    language: profileLanguage,
                    asrEngineID: selectedASRModelID?.rawValue,
                    autoSubmitKey: profileAutoSubmitKey
                )
            )
            resetDraft()
            appProfiles = controller.listVoiceAppProfiles()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectRunningApp(bundleID: String) {
        guard !bundleID.isEmpty,
              let option = runningAppOptions.first(where: { $0.bundleID == bundleID })
        else {
            profileBundleID = ""
            profileDisplayName = ""
            return
        }
        profileBundleID = option.bundleID
        profileDisplayName = option.name
    }

    private func deleteAppProfile(_ profile: VoiceAppProfile) {
        do {
            try controller.deleteVoiceAppProfile(id: profile.id)
            appProfiles = controller.listVoiceAppProfiles()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetDraft() {
        profileBundleID = ""
        profileDisplayName = ""
        selectedRunningAppBundleID = ""
        profilePrompt = ""
        profileLanguageRaw = "inherit"
        profileASRModelRaw = VoiceProfileASRModelSelection.inherit
        profileAutoSubmitKey = .none
        modelDownloadStatus = nil
        modelDownloadFraction = nil
    }

    private var profileLanguage: VoiceLanguage? {
        guard profileLanguageRaw != "inherit" else { return nil }
        return VoiceLanguage(rawValue: profileLanguageRaw)
    }

    private func autoSubmitLabel(for key: VoiceAutoSubmitKey) -> String {
        switch key {
        case .none:
            "None"
        case .returnKey:
            "Return"
        case .commandReturn:
            "Command-Return"
        }
    }

    private var runningAppPickerOptions: [String] {
        [""] + runningAppOptions.map(\.bundleID)
    }

    private func runningAppTitle(_ bundleID: String) -> String {
        guard !bundleID.isEmpty else { return "Choose app" }
        return runningAppOptions.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    private let profileLanguageOptions = [
        "inherit",
        VoiceLanguage.mixed.rawValue,
        VoiceLanguage.chinese.rawValue,
        VoiceLanguage.english.rawValue
    ]

    private func profileLanguageTitle(_ rawValue: String) -> String {
        switch rawValue {
        case "inherit":
            "Inherit"
        case VoiceLanguage.mixed.rawValue:
            "Mixed"
        case VoiceLanguage.chinese.rawValue:
            "Chinese"
        case VoiceLanguage.english.rawValue:
            "English"
        default:
            rawValue
        }
    }

    private func profileModelLabel(_ raw: String?) -> String {
        guard let modelID = VoiceASRModelID(storedIdentifier: raw) else {
            return "Inherit"
        }
        return modelID.title
    }
}

private enum VoiceProfileASRModelSelection {
    static let inherit = "inherit"
}

enum VoiceAppProfileEditorPresentation {
    static let sectionSubtitle = "Use app-specific overrides only when an app needs different voice behavior."
    static let modelSubtitle = "Usually Inherit. Override only when this app needs a different accuracy or memory tradeoff."

    static var modelOptions: [String] {
        [VoiceProfileASRModelSelection.inherit] + VoiceASRModelID.allCases.map(\.rawValue)
    }

    static func modelTitle(_ rawValue: String) -> String {
        guard rawValue != VoiceProfileASRModelSelection.inherit else {
            return "Inherit global model"
        }
        return VoiceASRModelID(storedIdentifier: rawValue)?.title ?? rawValue
    }
}

private struct VoiceProfileRunningAppOption: Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    static func available() -> [VoiceProfileRunningAppOption] {
        var seenBundleIDs = Set<String>()
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> VoiceProfileRunningAppOption? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier,
                      !seenBundleIDs.contains(bundleID)
                else {
                    return nil
                }
                seenBundleIDs.insert(bundleID)
                let appName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                return VoiceProfileRunningAppOption(
                    bundleID: bundleID,
                    name: appName?.isEmpty == false ? appName ?? bundleID : bundleID
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private enum VoiceModelDownloadPresenter {
    static func describe(_ progress: DownloadUtils.DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            "Listing model files..."
        case let .downloading(completedFiles, totalFiles):
            "Downloading \(completedFiles)/\(totalFiles) files..."
        case let .compiling(modelName):
            "Compiling \(modelName)..."
        }
    }
}

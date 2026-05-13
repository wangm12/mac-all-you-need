import Core
import SwiftUI

struct VoiceAppProfilesSection: View {
    let controller: AppController
    @Binding var errorMessage: String?
    @State private var appProfiles: [VoiceAppProfile]
    @State private var profileEnabled = true
    @State private var profileBundleID = ""
    @State private var profileDisplayName = ""
    @State private var profilePrompt = ""
    @State private var profileLanguageRaw = "inherit"
    @State private var profileASREngineID = "qwen3-asr-0.6b"
    @State private var profileAutoSubmitKey: VoiceAutoSubmitKey = .none

    init(controller: AppController, errorMessage: Binding<String?>) {
        self.controller = controller
        _errorMessage = errorMessage
        _appProfiles = State(initialValue: controller.listVoiceAppProfiles())
    }

    var body: some View {
        MAYNSection(
            title: "App Profiles",
            subtitle: "Override cleanup and paste behavior for specific macOS apps."
        ) {
            ForEach(Array(appProfiles.enumerated()), id: \.element.id) { offset, profile in
                MAYNSettingsRow(
                    title: profile.displayName,
                    subtitle: profile.bundleID,
                    minHeight: 54
                ) {
                    HStack(spacing: 10) {
                        StatusPill(text: profile.config.isEnabled ? "Enabled" : "Disabled", kind: profile.config.isEnabled ? .success : .neutral)
                        StatusPill(text: autoSubmitLabel(for: profile.config.autoSubmitKey), kind: .neutral)
                        Button {
                            deleteAppProfile(profile)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if offset != appProfiles.count - 1 {
                    MAYNDivider()
                }
            }

            if !appProfiles.isEmpty {
                MAYNDivider()
            }
            MAYNSettingsRow(
                title: "Profile enabled",
                subtitle: "New or updated profile will be active when saved."
            ) {
                Toggle("", isOn: $profileEnabled)
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Bundle ID") {
                TextField("", text: $profileBundleID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Display name") {
                TextField("", text: $profileDisplayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "ASR engine ID") {
                TextField("", text: $profileASREngineID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Language") {
                Picker("", selection: $profileLanguageRaw) {
                    Text("Inherit").tag("inherit")
                    Text("Mixed").tag(VoiceLanguage.mixed.rawValue)
                    Text("Chinese").tag(VoiceLanguage.chinese.rawValue)
                    Text("English").tag(VoiceLanguage.english.rawValue)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Auto-submit") {
                Picker("", selection: $profileAutoSubmitKey) {
                    ForEach(VoiceAutoSubmitKey.allCases, id: \.self) { key in
                        Text(autoSubmitLabel(for: key)).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Custom prompt",
                subtitle: "Optional cleanup instructions applied for this app.",
                minHeight: 92
            ) {
                TextEditor(text: $profilePrompt)
                    .font(.callout)
                    .frame(width: 300, height: 70)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.2))
                    }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Profile action") {
                Button("Save") { saveAppProfile() }
                    .disabled(profileBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveAppProfile() {
        do {
            let bundleID = profileBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let asrEngineID = profileASREngineID.trimmingCharacters(in: .whitespacesAndNewlines)
            try controller.upsertVoiceAppProfile(
                bundleID: bundleID,
                displayName: displayName.isEmpty ? bundleID : displayName,
                config: VoiceAppProfileConfig(
                    isEnabled: profileEnabled,
                    customPrompt: profilePrompt,
                    language: profileLanguage,
                    asrEngineID: asrEngineID.isEmpty ? nil : asrEngineID,
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
        profilePrompt = ""
        profileLanguageRaw = "inherit"
        profileASREngineID = "qwen3-asr-0.6b"
        profileAutoSubmitKey = .none
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
}

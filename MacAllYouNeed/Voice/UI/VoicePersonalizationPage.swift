import AppKit
import Core
import SwiftUI

struct VoicePersonalizationPage: View {
    let controller: AppController
    @State private var contexts: [VoicePersonalizationContext] = []
    @State private var settings: VoicePersonalizationSettings = .default
    @State private var showClearConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            MAYNSection(
                title: "Personal style",
                subtitle: "Describe how you'd like your dictation cleaned up. Applied globally."
            ) {
                MAYNSettingsRow(
                    title: "Style notes",
                    subtitle: "Optional. E.g. Remove filler words. Keep it casual.",
                    minHeight: 92
                ) {
                    TextEditor(text: styleNotesBinding)
                        .font(.callout)
                        .frame(width: MAYNControlMetrics.wideTextFieldWidth, height: 70)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2))
                        }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Learn from edits",
                    subtitle: "After you paste dictation and edit it, patterns are stored locally and encrypted. Older patterns are periodically summarized via your cleanup LLM provider."
                ) {
                    Toggle("", isOn: $settings.learnFromEditsEnabled)
                        .labelsHidden()
                        .onChange(of: settings.learnFromEditsEnabled) { _, _ in
                            saveSettings()
                        }
                }
            }

            MAYNSection(
                title: "Contexts",
                subtitle: "One row per app where learning has occurred. Tap to expand overrides."
            ) {
                if contexts.isEmpty {
                    MAYNSettingsRow(
                        title: "No personalization yet",
                        subtitle: "Personalization starts after you paste dictation and edit it."
                    ) { EmptyView() }
                } else {
                    ForEach(Array(contexts.enumerated()), id: \.element.id) { idx, ctx in
                        contextRow(ctx)
                        if idx != contexts.count - 1 { MAYNDivider() }
                    }
                }
            }

            MAYNSection(title: "Data") {
                MAYNSettingsRow(title: "Clear all personalization data") {
                    MAYNButton("Clear", role: .destructive) { showClearConfirm = true }
                }
            }

            if let err = errorMessage {
                MAYNSection(title: "") {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .onAppear { reload() }
        .alert("Clear all personalization data?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stored samples and summaries will be deleted. This cannot be undone.")
        }
    }

    // MARK: - Context row

    @ViewBuilder
    private func contextRow(_ ctx: VoicePersonalizationContext) -> some View {
        DisclosureGroup {
            overrideRows(ctx)
        } label: {
            HStack {
                appIcon(bundleID: ctx.bundleID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.displayName).font(.body)
                    if ctx.sampleCount > 0 {
                        Text("\(ctx.sampleCount) sample\(ctx.sampleCount == 1 ? "" : "s")\(ctx.lastLearnedAt.map { " · " + $0.relativeLabel } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No samples yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { ctx.enabled },
                    set: { enabled in toggleContext(ctx, enabled: enabled) }
                ))
                .labelsHidden()
                MAYNButton(role: .destructive, height: 24, action: { resetContext(ctx) }) {
                    Image(systemName: "xmark")
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func overrideRows(_ ctx: VoicePersonalizationContext) -> some View {
        VStack(spacing: 0) {
            MAYNDivider()
            MAYNSettingsRow(title: "ASR model") {
                MAYNDropdown(
                    selection: Binding(
                        get: { ctx.asrModelID ?? "inherit" },
                        set: { updateASRModel(ctx, modelID: $0 == "inherit" ? nil : $0) }
                    ),
                    options: ["inherit"] + VoiceASRModelID.allCases.map(\.rawValue),
                    title: { id in
                        id == "inherit" ? "Inherit" : VoiceASRModelID(rawValue: id)?.title ?? id
                    }
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Auto-submit") {
                MAYNDropdown(
                    selection: Binding(
                        get: { ctx.autoSubmitKey?.rawValue ?? VoiceAutoSubmitKey.none.rawValue },
                        set: { updateAutoSubmit(ctx, key: VoiceAutoSubmitKey(rawValue: $0) ?? .none) }
                    ),
                    options: VoiceAutoSubmitKey.allCases.map(\.rawValue),
                    title: { raw in
                        switch VoiceAutoSubmitKey(rawValue: raw) {
                        case .returnKey: "Return"
                        case .commandReturn: "Command-Return"
                        default: "None"
                        }
                    }
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Custom prompt", minHeight: 80) {
                TextEditor(text: Binding(
                    get: { ctx.customPromptOverride ?? "" },
                    set: { updateCustomPrompt(ctx, prompt: $0) }
                ))
                .font(.callout)
                .frame(width: MAYNControlMetrics.wideTextFieldWidth, height: 60)
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)) }
            }
        }
    }

    @ViewBuilder
    private func appIcon(bundleID: String) -> some View {
        if bundleID == VoicePersonalizationContext.globalBundleID {
            Image(systemName: "globe")
                .font(.title2)
                .frame(width: 28, height: 28)
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                  let icon = app.icon
        {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "app.dashed")
                .font(.title2)
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var styleNotesBinding: Binding<String> {
        Binding(
            get: { contexts.first(where: { $0.bundleID == VoicePersonalizationContext.globalBundleID })?.styleNotes ?? "" },
            set: { saveStyleNotes($0) }
        )
    }

    private func saveStyleNotes(_ notes: String) {
        let globalDraft = VoicePersonalizationContextDraft(
            bundleID: VoicePersonalizationContext.globalBundleID,
            displayName: VoicePersonalizationContext.globalDisplayName,
            styleNotes: notes.isEmpty ? nil : notes
        )
        do {
            try controller.upsertPersonalizationContext(globalDraft)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSettings() {
        controller.applyVoicePersonalizationSettings(settings)
    }

    private func toggleContext(_ ctx: VoicePersonalizationContext, enabled: Bool) {
        let draft = VoicePersonalizationContextDraft(
            bundleID: ctx.bundleID,
            displayName: ctx.displayName,
            enabled: enabled,
            asrModelID: ctx.asrModelID,
            autoSubmitKey: ctx.autoSubmitKey,
            customPromptOverride: ctx.customPromptOverride,
            styleNotes: ctx.styleNotes
        )
        do {
            try controller.upsertPersonalizationContext(draft)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateASRModel(_ ctx: VoicePersonalizationContext, modelID: String?) {
        let draft = VoicePersonalizationContextDraft(
            bundleID: ctx.bundleID,
            displayName: ctx.displayName,
            enabled: ctx.enabled,
            asrModelID: modelID,
            autoSubmitKey: ctx.autoSubmitKey,
            customPromptOverride: ctx.customPromptOverride,
            styleNotes: ctx.styleNotes
        )
        try? controller.upsertPersonalizationContext(draft)
        reload()
    }

    private func updateAutoSubmit(_ ctx: VoicePersonalizationContext, key: VoiceAutoSubmitKey) {
        let draft = VoicePersonalizationContextDraft(
            bundleID: ctx.bundleID,
            displayName: ctx.displayName,
            enabled: ctx.enabled,
            asrModelID: ctx.asrModelID,
            autoSubmitKey: key == .none ? nil : key,
            customPromptOverride: ctx.customPromptOverride,
            styleNotes: ctx.styleNotes
        )
        try? controller.upsertPersonalizationContext(draft)
        reload()
    }

    private func updateCustomPrompt(_ ctx: VoicePersonalizationContext, prompt: String) {
        let draft = VoicePersonalizationContextDraft(
            bundleID: ctx.bundleID,
            displayName: ctx.displayName,
            enabled: ctx.enabled,
            asrModelID: ctx.asrModelID,
            autoSubmitKey: ctx.autoSubmitKey,
            customPromptOverride: prompt.isEmpty ? nil : prompt,
            styleNotes: ctx.styleNotes
        )
        try? controller.upsertPersonalizationContext(draft)
        reload()
    }

    private func resetContext(_ ctx: VoicePersonalizationContext) {
        do {
            try controller.deletePersonalizationContext(id: ctx.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try controller.clearPersonalizationData()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        contexts = controller.listPersonalizationContexts()
        settings = controller.voicePersonalizationSettings()
        errorMessage = nil
    }
}

private extension Date {
    var relativeLabel: String {
        let diff = -timeIntervalSinceNow
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }
}

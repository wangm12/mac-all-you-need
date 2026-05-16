import AppKit
import Core
import SwiftUI

struct VoicePersonalizationPage: View {
    let controller: AppController
    @State private var contexts: [VoicePersonalizationContext] = []
    @State private var settings: VoicePersonalizationSettings = .default
    @State private var trainingExampleCount = 0
    @State private var showClearConfirm = false
    @State private var showClearTrainingConfirm = false
    @State private var showManageApps = false
    @State private var errorMessage: String?
    @State private var showWritingStyle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            MAYNSection(
                title: "Personalization",
                subtitle: "Let the app learn how you clean up dictation."
            ) {
                MAYNSettingsRow(
                    title: "Learn from edits",
                    subtitle: "After you paste dictation and edit it, patterns are stored locally and encrypted."
                ) {
                    Toggle("", isOn: $settings.learnFromEditsEnabled)
                        .labelsHidden()
                        .onChange(of: settings.learnFromEditsEnabled) { _, _ in
                            saveSettings()
                        }
                }
                MAYNDivider()
                writingStyleRow
            }

            MAYNSection(
                title: "Apps",
                subtitle: "Choose where learned cleanup preferences are allowed."
            ) {
                MAYNSettingsRow(
                    title: "App controls",
                    subtitle: appLearningSummary
                ) {
                    MAYNButton("Manage...", action: { showManageApps = true })
                        .disabled(appContexts.isEmpty)
                }
            }

            MAYNSection(
                title: "Training data",
                subtitle: "Saved locally for future model improvement. Not uploaded."
            ) {
                MAYNSettingsRow(
                    title: "Save training examples",
                    subtitle: "Stores encrypted audio, raw text, cleaned text, and final edited text on this Mac."
                ) {
                    Toggle("", isOn: $settings.saveTrainingExamplesEnabled)
                        .labelsHidden()
                        .onChange(of: settings.saveTrainingExamplesEnabled) { _, _ in
                            saveSettings()
                        }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Saved examples",
                    subtitle: "\(trainingExampleCount) local example\(trainingExampleCount == 1 ? "" : "s") saved."
                ) {
                    MAYNButton("Clear", role: .destructive) { showClearTrainingConfirm = true }
                        .disabled(trainingExampleCount == 0)
                }
            }

            MAYNSection(title: "Reset") {
                MAYNSettingsRow(
                    title: "Reset learned style",
                    subtitle: "Delete stored samples, summaries, app preferences, and writing notes."
                ) {
                    MAYNButton("Reset", role: .destructive) { showClearConfirm = true }
                }
            }

            if let err = errorMessage {
                MAYNSection(title: "") {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showManageApps) {
            VoicePersonalizationAppsSheet(
                contexts: appContexts,
                onToggle: toggleContext,
                onForget: resetContext
            )
        }
        .alert("Reset learned style?", isPresented: $showClearConfirm) {
            Button("Reset", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stored samples, summaries, app preferences, and writing notes will be deleted. This cannot be undone.")
        }
        .alert("Clear saved training examples?", isPresented: $showClearTrainingConfirm) {
            Button("Clear", role: .destructive) { clearTrainingExamples() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved training audio and final edited text will be deleted from this Mac. Personalization can stay on.")
        }
    }

    // MARK: - Rows

    private var writingStyleRow: some View {
        VStack(spacing: 0) {
            Button {
                showWritingStyle.toggle()
            } label: {
                HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showWritingStyle ? 90 : 0))
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Writing style").font(.body)
                        Text(styleNotesSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
                .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
                .frame(minHeight: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Writing style")
            .accessibilityValue(showWritingStyle ? "Expanded" : "Collapsed")

            if showWritingStyle {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Notes",
                    subtitle: "Optional. Applied globally.",
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
            }
        }
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: showWritingStyle)
    }

    private var appContexts: [VoicePersonalizationContext] {
        contexts.filter { !$0.isGlobal }
    }

    private var appLearningSummary: String {
        guard !appContexts.isEmpty else {
            return "No app learning yet."
        }
        let sampleCount = appContexts.reduce(0) { $0 + $1.sampleCount }
        return "Learned from \(sampleCount) edit\(sampleCount == 1 ? "" : "s") in \(appContexts.count) app\(appContexts.count == 1 ? "" : "s")."
    }

    private var styleNotesSummary: String {
        let notes = styleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? "Optional guide for tone and cleanup." : "Custom notes set."
    }

    private var styleNotes: String {
        contexts.first(where: { $0.bundleID == VoicePersonalizationContext.globalBundleID })?.styleNotes ?? ""
    }

    // MARK: - Actions

    private var styleNotesBinding: Binding<String> {
        Binding(
            get: { styleNotes },
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

    private func clearTrainingExamples() {
        do {
            try controller.clearVoiceTrainingExamples()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        contexts = controller.listPersonalizationContexts()
        settings = controller.voicePersonalizationSettings()
        trainingExampleCount = controller.voiceTrainingExampleCount()
        errorMessage = nil
    }
}

private struct VoicePersonalizationAppsSheet: View {
    let contexts: [VoicePersonalizationContext]
    let onToggle: (VoicePersonalizationContext, Bool) -> Void
    let onForget: (VoicePersonalizationContext) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Apps")
                        .font(.title3.weight(.semibold))
                    Text("Pause personalization or forget app-specific learning data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MAYNButton("Done", role: .primary) { dismiss() }
            }

            MAYNTextField(placeholder: "Search apps", text: $searchText, width: 320)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredContexts.isEmpty {
                        Text("No matching apps")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(Array(filteredContexts.enumerated()), id: \.element.id) { idx, ctx in
                            appRow(ctx)
                            if idx != filteredContexts.count - 1 { MAYNDivider() }
                        }
                    }
                }
            }
            .frame(width: 560, height: 360)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius))
        }
        .padding(20)
        .frame(width: 600)
    }

    private var filteredContexts: [VoicePersonalizationContext] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contexts }
        return contexts.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    private func appRow(_ ctx: VoicePersonalizationContext) -> some View {
        HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
            VoicePersonalizationAppIcon(bundleID: ctx.bundleID)

            VStack(alignment: .leading, spacing: 2) {
                Text(ctx.displayName).font(.body)
                Text(contextSampleLabel(ctx))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { ctx.enabled },
                set: { enabled in onToggle(ctx, enabled) }
            ))
            .labelsHidden()
            .help(ctx.enabled ? "Pause personalization for this app" : "Use learned style in this app")

            MAYNButton("Forget data", role: .destructive, height: 24) {
                onForget(ctx)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .frame(minHeight: 64)
    }

    private func contextSampleLabel(_ ctx: VoicePersonalizationContext) -> String {
        let countLabel = "\(ctx.sampleCount) edit\(ctx.sampleCount == 1 ? "" : "s")"
        guard let lastLearnedAt = ctx.lastLearnedAt else { return countLabel }
        return "\(countLabel) · \(lastLearnedAt.relativeLabel)"
    }
}

private struct VoicePersonalizationAppIcon: View {
    let bundleID: String

    var body: some View {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
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

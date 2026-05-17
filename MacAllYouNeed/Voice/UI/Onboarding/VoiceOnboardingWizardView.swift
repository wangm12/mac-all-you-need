import AppKit
import ApplicationServices
import AVFAudio
import AVFoundation
import Core
import FluidAudio
import Platform
import SwiftUI

// swiftlint:disable file_length
struct VoiceOnboardingWizardView: View {
    let controller: AppController
    @State private var step: VoiceOnboardingStep
    @State private var tryItSucceeded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(controller: AppController) {
        self.controller = controller
        let progress = VoiceOnboardingProgressStore.load()
        _step = State(initialValue: progress.isCompleted ? .welcome : progress.currentStep)
    }

    var body: some View {
        SetupWizardShell(
            title: "Voice Setup",
            subtitle: "Dictation workflow",
            steps: stepDescriptors,
            currentStep: step,
            canGoBack: step.previous != nil,
            canSkip: canSkipCurrentStep,
            primaryTitle: primaryTitle,
            canAdvance: canAdvanceCurrentStep,
            back: { move(to: step.previous ?? step) },
            skip: skipCurrentStep,
            primaryAction: step == .done ? finish : advance
        ) {
            currentStepView
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(width: 860, height: 640)
        .onAppear { VoiceOnboardingProgressStore.saveStep(step) }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .welcome:
            VoiceWelcomeStepView()
        case .microphone:
            VoiceMicrophoneStepView(autoAdvance: { move(to: .accessibility) })
        case .accessibility:
            VoiceAccessibilityStepView(autoAdvance: { move(to: .asr) })
        case .asr:
            VoiceASRStepView()
        case .llm:
            VoiceLLMStepView(controller: controller)
        case .hotkey:
            VoiceHotkeyStepView(controller: controller)
        case .languages:
            VoiceLanguagesStepView()
        case .tryIt:
            VoiceTryItStepView(controller: controller) {
                tryItSucceeded = true
            }
        case .done:
            VoiceDoneStepView()
        }
    }

    private var canSkipCurrentStep: Bool {
        step.canSkip
    }

    private var canAdvanceCurrentStep: Bool {
        step != .tryIt || tryItSucceeded
    }

    private var primaryTitle: String {
        switch step {
        case .welcome:
            "Get Started"
        case .done:
            "Done"
        case .microphone, .accessibility, .asr, .llm, .hotkey, .languages, .tryIt:
            "Continue"
        }
    }

    private var stepDescriptors: [SetupStepDescriptor<VoiceOnboardingStep>] {
        let currentIndex = VoiceOnboardingStep.orderedCases.firstIndex(of: step) ?? 0
        return VoiceOnboardingStep.orderedCases.enumerated().map { index, candidate in
            SetupStepDescriptor(
                id: candidate,
                title: candidate.title,
                subtitle: candidate.setupSubtitle,
                symbol: candidate.setupSymbol,
                isCompleted: index < currentIndex
            )
        }
    }

    private func advance() {
        guard let next = step.next else {
            finish()
            return
        }
        move(to: next)
    }

    private func skipCurrentStep() {
        if step == .llm {
            controller.disableVoiceCleanup()
        }
        advance()
    }

    private func move(to newStep: VoiceOnboardingStep) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
                step = newStep
            }
        }
        VoiceOnboardingProgressStore.saveStep(newStep)
    }

    private func finish() {
        VoiceOnboardingProgressStore.markCompleted()
        controller.closeVoiceOnboarding()
        controller.showMainWindowIfReady()
    }
}

private extension VoiceOnboardingStep {
    var setupSubtitle: String {
        switch self {
        case .welcome:
            "Overview"
        case .microphone:
            "Capture audio"
        case .accessibility:
            "Paste anywhere"
        case .asr:
            "Local engine"
        case .llm:
            "Cleanup"
        case .hotkey:
            "Activation"
        case .languages:
            "Recognition bias"
        case .tryIt:
            "Confirm"
        case .done:
            "Finish"
        }
    }

    var setupSymbol: String {
        switch self {
        case .welcome:
            "mic.badge.plus"
        case .microphone:
            "mic"
        case .accessibility:
            "accessibility"
        case .asr:
            "waveform"
        case .llm:
            "text.bubble"
        case .hotkey:
            "keyboard"
        case .languages:
            "globe"
        case .tryIt:
            "square.and.pencil"
        case .done:
            "checkmark"
        }
    }
}

private struct VoiceWelcomeStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let phrases = [
        "Write emails 5x faster",
        "用中英文混合 dictate",
        "Translate as you speak",
        "Polish your writing automatically"
    ]
    @State private var phraseIndex = 0
    private let timer = Timer.publish(every: 2.1, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "mic.badge.plus",
            title: phrases[phraseIndex],
            subtitle: "Press a shortcut, speak naturally, and paste polished text into any Mac app."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Local ASR keeps audio on this Mac by default.", systemImage: "lock")
                Label("Mixed Chinese and English dictation is supported.", systemImage: "globe")
                Label("Cleanup can be local or provider-based, depending on your settings.", systemImage: "text.bubble")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
            .id(phraseIndex)
            .transition(.opacity)
        }
        .onReceive(timer) { _ in
            if reduceMotion {
                phraseIndex = (phraseIndex + 1) % phrases.count
            } else {
                withAnimation(MAYNMotion.instructionAnimation(reduceMotion: reduceMotion)) {
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
    }
}

private struct VoiceMicrophoneStepView: View {
    let autoAdvance: () -> Void
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var audio = AudioCaptureService()
    @State private var isCapturing = false
    @State private var visualLevel = 0.0
    @State private var audioDetectedAt: Date?
    @State private var didAutoAdvance = false
    @State private var showsInstruction = false
    @State private var statusMessage = "macOS will ask for permission when you continue."
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "mic",
            title: "Allow microphone access",
            subtitle: "Voice dictation needs microphone access to capture audio locally before transcription."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionCard(
                    title: "Microphone",
                    reason: "macOS will ask once. After access is granted, speak briefly to confirm input level.",
                    state: permissionCardState,
                    actionTitle: permission == .authorized ? "Microphone granted" : "Request access",
                    action: requestPermission
                )
                if showsInstruction && permission != .authorized {
                    InstructionStrip(
                        text: "Choose Allow in the macOS microphone prompt.",
                        symbol: "mic.badge.plus"
                    )
                }
                if permission == .authorized {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: visualLevel, total: 1)
                        Text("This step advances automatically after audio is detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                }
                MAYNButton("Open Microphone Settings") {
                    showsInstruction = true
                    openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
                permissionLabel
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if permission == .authorized {
                startCapture()
            }
        }
        .onDisappear {
            stopCapture()
        }
        .onReceive(timer) { _ in
            updateAudioDetection()
        }
    }

    private var permissionCardState: PermissionCard.StateKind {
        switch permission {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .needed
        @unknown default:
            .needed
        }
    }

    @ViewBuilder
    private var permissionLabel: some View {
        switch permission {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.primary)
        case .denied, .restricted:
            Label("Permission is blocked. Enable it in System Settings.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        case .notDetermined:
            Text("Waiting for permission.")
                .foregroundStyle(.secondary)
        @unknown default:
            Text("Unknown microphone permission state.")
                .foregroundStyle(.secondary)
        }
    }

    private func requestPermission() {
        showsInstruction = permission != .authorized
        Task {
            let granted = await Self.requestRecordPermission()
            permission = granted ? .authorized : .denied
            statusMessage = granted
                ? "Microphone granted. Starting live level check..."
                : "Microphone access was denied."
            if granted {
                showsInstruction = false
                startCapture()
            }
        }
    }

    private func startCapture() {
        guard !isCapturing else { return }
        do {
            try audio.start()
            isCapturing = true
            statusMessage = "Listening for input level..."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func stopCapture() {
        _ = audio.stop()
        isCapturing = false
        audioDetectedAt = nil
    }

    private func updateAudioDetection() {
        guard permission == .authorized, isCapturing, !didAutoAdvance else { return }
        let peak = Double(audio.peakLevel)
        visualLevel = min(max(peak * 4, 0), 1)
        guard peak > 0.02 else { return }

        let now = Date()
        if audioDetectedAt == nil {
            audioDetectedAt = now
            statusMessage = "Audio detected. Keep speaking briefly..."
        }
        guard let audioDetectedAt,
              now.timeIntervalSince(audioDetectedAt) >= 1.5
        else {
            return
        }
        didAutoAdvance = true
        stopCapture()
        autoAdvance()
    }

    private static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private struct VoiceAccessibilityStepView: View {
    let autoAdvance: () -> Void
    @State private var granted = AXIsProcessTrusted()
    @State private var showsInstruction = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "accessibility",
            title: "Type into any app",
            subtitle: "Accessibility lets Mac All You Need paste dictated text into Cursor, Notes, browsers, and other apps."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let instruction = PermissionInstructionTarget.accessibility.instruction(appName: "Mac All You Need")
                PermissionCard(
                    title: "Accessibility",
                    reason: "Required so voice output can be inserted into the currently focused app.",
                    state: granted ? .granted : .needed,
                    actionTitle: "Open System Settings"
                ) {
                    showsInstruction = true
                    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                    openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                if showsInstruction && !granted {
                    InstructionStrip(
                        text: instruction.primaryText,
                        appName: "Mac All You Need",
                        symbol: instruction.symbol,
                        secondaryText: instruction.secondaryText,
                        dragAppURL: Bundle.main.bundleURL,
                        actionTitle: "Open Settings"
                    ) {
                        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                }
                if granted {
                    StatusPill(text: "Ready to paste dictated text", kind: .neutral)
                } else {
                    Text("This step advances automatically once macOS reports the permission as granted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(timer) { _ in
            let nowGranted = AXIsProcessTrusted()
            if nowGranted, !granted {
                granted = true
                showsInstruction = false
                autoAdvance()
            } else {
                granted = nowGranted
            }
        }
    }
}

private struct VoiceASRStepView: View {
    @State private var selectedModelID = VoiceASRSettingsStore.load().modelID
    @State private var isPreparing = false
    @State private var downloadFraction: Double?
    @State private var showsMoreOptions = false
    @State private var statusMessage = "Choose a local recognition model. Missing models download before dictation uses them."

    private let primaryOptions = VoiceASRModelID.allCases
    private let moreOptions: [VoiceASROption] = [
        VoiceASROption(
            id: "whisper-large-v3-turbo",
            title: "Whisper large-v3 turbo",
            subtitle: "Large multilingual model, planned for 8d",
            available: false
        ),
        VoiceASROption(id: "soniox", title: "Soniox", subtitle: "Cloud BYOK, planned for 8d", available: false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose speech recognition")
                .font(.title)
                .bold()
            Text("Audio stays local by default. Future engines are visible here so the setup matches the v1 catalog.")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(primaryOptions) { option in
                    modelButton(option)
                }
            }
            DisclosureGroup("More options", isExpanded: $showsMoreOptions) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(moreOptions) { option in
                        optionButton(option)
                    }
                }
            }
            HStack {
                MAYNButton(isPreparing ? "Downloading..." : actionTitle(for: selectedModelID), role: .primary) {
                    selectModel(selectedModelID)
                }
                .disabled(isPreparing)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let downloadFraction {
                ProgressView(value: downloadFraction)
            }
            Spacer()
        }
    }

    private func modelButton(_ modelID: VoiceASRModelID) -> some View {
        Button {
            selectModel(modelID)
        } label: {
            VoiceASRModelOnboardingCard(
                modelID: modelID,
                isSelected: selectedModelID == modelID,
                isDownloaded: isDownloaded(modelID),
                isPreparing: isPreparing && selectedModelID == modelID,
                downloadFraction: selectedModelID == modelID ? downloadFraction : nil
            )
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
    }

    private func optionButton(_ option: VoiceASROption) -> some View {
        Button {} label: {
            VoiceASROptionView(option: option, isSelected: false)
        }
        .buttonStyle(.plain)
        .disabled(true)
    }

    private func selectModel(_ modelID: VoiceASRModelID) {
        selectedModelID = modelID
        guard !isDownloaded(modelID) else {
            saveSelectedModel(modelID)
            statusMessage = "\(modelID.title) is ready and selected."
            return
        }
        prepareModel(modelID)
    }

    private func prepareModel(_ modelID: VoiceASRModelID) {
        guard #available(macOS 15, *) else {
            statusMessage = "\(modelID.title) preparation requires macOS 15 or later."
            return
        }
        guard !isPreparing else { return }
        isPreparing = true
        downloadFraction = 0
        statusMessage = "Downloading \(modelID.title) into the local model cache..."
        Task {
            do {
                _ = try await Qwen3AsrModels.download(variant: modelID.variant) { progress in
                    Task { @MainActor in
                        downloadFraction = progress.fractionCompleted
                        statusMessage = Self.describe(progress, modelID: modelID)
                    }
                }
                await MainActor.run {
                    saveSelectedModel(modelID)
                    statusMessage = "\(modelID.title) is ready and selected."
                    downloadFraction = 1
                    isPreparing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    downloadFraction = nil
                    isPreparing = false
                }
            }
        }
    }

    private func saveSelectedModel(_ modelID: VoiceASRModelID) {
        var settings = VoiceASRSettingsStore.load()
        settings.modelID = modelID
        VoiceASRSettingsStore.save(settings)
    }

    private func isDownloaded(_ modelID: VoiceASRModelID) -> Bool {
        guard #available(macOS 15, *) else { return false }
        return Qwen3AsrModels.modelsExist(
            at: Qwen3AsrModels.defaultCacheDirectory(variant: modelID.variant)
        )
    }

    private func actionTitle(for modelID: VoiceASRModelID) -> String {
        isDownloaded(modelID) ? "Use selected model" : "Download & Use"
    }

    private static func describe(_ progress: DownloadUtils.DownloadProgress, modelID: VoiceASRModelID) -> String {
        switch progress.phase {
        case .listing:
            "Listing \(modelID.title) files..."
        case let .downloading(completedFiles, totalFiles):
            "Downloading \(modelID.title) files \(completedFiles)/\(totalFiles)..."
        case let .compiling(modelName):
            "Compiling \(modelName)..."
        }
    }
}

private struct VoiceASROption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let available: Bool
}

private struct VoiceASRModelOnboardingCard: View {
    let modelID: VoiceASRModelID
    let isSelected: Bool
    let isDownloaded: Bool
    let isPreparing: Bool
    let downloadFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(modelID.title)
                    .font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Text(modelID.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                StatusPill(text: modelID.diskLabel, kind: .neutral)
                StatusPill(text: statusText, kind: statusKind)
            }
            if let downloadFraction {
                ProgressView(value: downloadFraction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        if isPreparing { return "Downloading" }
        if isDownloaded { return "Downloaded" }
        return "Not installed"
    }

    private var statusKind: StatusPill.Kind {
        if isPreparing { return .progress }
        if isDownloaded { return .success }
        return .warning
    }
}

private struct VoiceASROptionView: View {
    let option: VoiceASROption
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(option.title)
                    .font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Text(option.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !option.available {
                Text("Coming in multi-engine phase")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.primary.opacity(0.45) : Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(option.available ? 1 : 0.55)
    }
}

private struct VoiceLLMStepView: View {
    let controller: AppController
    @State private var cleanupEnabled: Bool
    @State private var provider: VoiceCleanupProviderKind
    @State private var model: String
    @State private var learnFromEdits: Bool
    @State private var baseURLString: String
    @State private var apiKey: String
    @State private var timeoutSeconds: Int
    @State private var statusMessage: String?
    @State private var isTesting = false

    init(controller: AppController) {
        self.controller = controller
        let settings = controller.voiceCleanupSettings()
        _cleanupEnabled = State(initialValue: settings.isEnabled)
        _provider = State(initialValue: settings.provider)
        _model = State(initialValue: settings.model)
        _baseURLString = State(initialValue: settings.baseURLString)
        _apiKey = State(initialValue: controller.voiceCleanupAPIKey(for: settings.provider))
        _timeoutSeconds = State(initialValue: settings.timeoutSeconds)
        _learnFromEdits = State(initialValue: controller.voicePersonalizationSettings().learnFromEditsEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI cleanup")
                .font(.title)
                .bold()
            Text("This step is optional. Local filler cleanup and your dictionary still work when AI cleanup is off.")
                .foregroundStyle(.secondary)
            Text("Cloud cleanup sends transcript text to the provider you choose. Audio stays local.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Enable AI cleanup", isOn: $cleanupEnabled)
            HStack(spacing: 10) {
                ForEach(VoiceCleanupProviderKind.allCases) { kind in
                    Button {
                        provider = kind
                    } label: {
                        VoiceCleanupProviderCard(
                            provider: kind,
                            isSelected: provider == kind
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            MAYNTextField(placeholder: "Model", text: $model, width: 360)
            MAYNTextField(placeholder: "Base URL", text: $baseURLString, width: 360)
            MAYNSecureField(placeholder: "API key", text: $apiKey, width: 360)
            HStack {
                Text("Timeout")
                Spacer()
                MAYNNumericStepper(
                    text: "\(timeoutSeconds)s",
                    value: $timeoutSeconds,
                    range: 1...30,
                    presets: [3, 5, 7, 10, 15, 30],
                    suffix: "s"
                )
            }
            HStack {
                MAYNButton(isTesting ? "Testing..." : "Test") { testSettings() }
                    .disabled(isTesting)
                MAYNButton("Apply", role: .primary) { applySettings() }
                MAYNButton("Skip AI cleanup") {
                    cleanupEnabled = false
                    controller.disableVoiceCleanup()
                    statusMessage = "AI cleanup disabled. Local cleanup remains active."
                }
            }
            Divider()
            Toggle(isOn: $learnFromEdits) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Improve cleanup over time by learning from your edits")
                        .font(.body)
                    Text("Edit samples are stored locally and encrypted. Older samples are summarized via your selected cleanup LLM provider to refine your style profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: learnFromEdits) { _, value in
                var s = controller.voicePersonalizationSettings()
                s.learnFromEditsEnabled = value
                controller.applyVoicePersonalizationSettings(s)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onChange(of: provider) { _, nextProvider in
            model = nextProvider.defaultModel
            baseURLString = nextProvider.defaultBaseURLString
            apiKey = controller.voiceCleanupAPIKey(for: nextProvider)
        }
    }

    private var draft: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: provider,
            model: model,
            baseURLString: baseURLString,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func testSettings() {
        isTesting = true
        statusMessage = "Sending provider ping..."
        Task {
            let message = await controller.testVoiceCleanupSettings(draft, apiKey: apiKey)
            await MainActor.run {
                statusMessage = message
                isTesting = false
            }
        }
    }

    private func applySettings() {
        do {
            try controller.applyVoiceCleanupSettings(draft, apiKey: apiKey)
            statusMessage = "Cleanup settings saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct VoiceCleanupProviderCard: View {
    let provider: VoiceCleanupProviderKind
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.primary.opacity(0.45) : Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch provider {
        case .anthropic:
            "Claude Haiku 4.5"
        case .openAICompatible:
            "OpenAI gpt-5-nano"
        case .ollama:
            "Ollama"
        }
    }

    private var subtitle: String {
        switch provider {
        case .anthropic:
            "Recommended cloud cleanup"
        case .openAICompatible:
            "OpenAI-compatible endpoint"
        case .ollama:
            "Local cleanup provider"
        }
    }
}

private struct VoiceHotkeyStepView: View {
    let controller: AppController
    @State private var shortcut: HotkeyDescriptor
    @State private var mode: VoiceActivationMode
    @State private var hybridThresholdMs = 500.0
    @State private var statusMessage: String?
    @State private var shortcutIssueMessage: String?
    @State private var showsHUDPreview = false

    init(controller: AppController) {
        self.controller = controller
        let settings = VoiceActivationSettingsStore.load()
        _shortcut = State(initialValue: settings.shortcut)
        _mode = State(initialValue: settings.mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set your voice shortcut")
                .font(.title)
                .bold()
            Text(
                "Default is \(VoiceActivationSettings.default.shortcut.display). "
                    + "Fn / Globe is optional because it can conflict with input switching."
            )
            .foregroundStyle(.secondary)
            VoiceKeyboardPreview(shortcutDisplay: shortcut.display)
            HStack {
                Text("Shortcut")
                Spacer()
                HotkeyRecorderControl(
                    descriptor: shortcutBinding,
                    issueMessage: shortcutIssueMessage,
                    candidateIssueMessage: { shortcutCandidateIssueMessage($0) },
                    defaultDescriptor: VoiceActivationSettings.default.shortcut,
                    recorderWidth: 140,
                    recorderHeight: 26,
                    errorWidth: 220,
                    alignment: .trailing,
                    errorFrameAlignment: .trailing,
                    reset: { applyShortcut(VoiceActivationSettings.default.shortcut) }
                )
            }
            VoiceActivationModePicker(mode: activationModeBinding)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Hybrid threshold")
                    Slider(value: $hybridThresholdMs, in: 200 ... 1200, step: 50)
                    Text("\(Int(hybridThresholdMs))ms")
                        .monospacedDigit()
                }
                .disabled(true)
                Text("Hybrid and Auto-VAD are visible here for the v1 setup catalog; runtime support lands in the multi-engine phase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                MAYNButton("Test now") {
                    showsHUDPreview = true
                    statusMessage = "HUD preview only. Recording will not start from this button."
                }
            }
            if showsHUDPreview {
                VoiceHUDPreview()
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var shortcutBinding: Binding<HotkeyDescriptor> {
        Binding(
            get: { shortcut },
            set: { descriptor in
                applyShortcut(descriptor)
            }
        )
    }

    private var activationModeBinding: Binding<VoiceActivationMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                applySettingsIfValid()
            }
        )
    }

    private func applyShortcut(_ descriptor: HotkeyDescriptor) {
        shortcut = descriptor
        applySettingsIfValid()
    }

    private func shortcutCandidateIssueMessage(_ descriptor: HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(forVoiceShortcut: descriptor, appHotkeys: HotkeyMapStore.load())?.message
    }

    private func applySettingsIfValid() {
        if let issue = HotkeyValidation.issue(forVoiceShortcut: shortcut, appHotkeys: HotkeyMapStore.load()) {
            shortcutIssueMessage = issue.message
            statusMessage = issue.message
            return
        }

        do {
            try controller.applyVoiceActivationSettings(VoiceActivationSettings(shortcut: shortcut, mode: mode))
            shortcutIssueMessage = nil
            statusMessage = "Voice shortcut saved."
        } catch {
            shortcutIssueMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }
}

private struct VoiceKeyboardPreview: View {
    let shortcutDisplay: String

    var body: some View {
        HStack(spacing: 6) {
            ShortcutChip(text: shortcutDisplay, height: 34)
            Text("Current shortcut")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
    }
}

private struct VoiceActivationModePicker: View {
    @Binding var mode: VoiceActivationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activation mode")
                .font(.headline)
            FunctionSegmentedTabStrip(
                tabs: Array(VoiceActivationMode.allCases),
                selection: mode,
                fillsAvailableWidth: true,
                size: .control
            ) { nextMode in
                mode = nextMode
            }
            HStack(spacing: 10) {
                Label("Hybrid", systemImage: "clock")
                Label("Auto-VAD", systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct VoiceHUDPreview: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.primary)
            Text("Listening")
                .font(.headline)
            ProgressView(value: 0.55)
                .frame(width: 140)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct VoiceLanguagesStepView: View {
    @State private var selected: Set<VoiceOnboardingLanguage>
    @State private var autoDetectEverything: Bool
    @State private var statusMessage: String?

    init() {
        let selection = VoiceOnboardingProgressStore.loadLanguageSelection()
        _selected = State(initialValue: Set(selection.selectedLanguages))
        _autoDetectEverything = State(initialValue: selection.autoDetectEverything)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick languages")
                .font(.title)
                .bold()
            Text("Use Auto-detect for mixed Chinese and English. Single-language choices bias the current Qwen3-ASR engine.")
                .foregroundStyle(.secondary)
            Toggle("Auto-detect language", isOn: $autoDetectEverything)
                .onChange(of: autoDetectEverything) { _, _ in save() }
            ForEach(VoiceOnboardingLanguage.allCases) { language in
                Toggle(language.label, isOn: binding(for: language))
                    .disabled(autoDetectEverything)
                    .opacity(autoDetectEverything ? 0.55 : 1)
            }
            HStack {
                MAYNButton("Apply languages", role: .primary) { save() }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func binding(for language: VoiceOnboardingLanguage) -> Binding<Bool> {
        Binding {
            selected.contains(language)
        } set: { isOn in
            if isOn {
                selected.insert(language)
            } else {
                selected.remove(language)
            }
        }
    }

    private func save() {
        let selection = VoiceOnboardingLanguageSelection(
            selectedLanguages: Array(selected),
            autoDetectEverything: autoDetectEverything
        )
        VoiceOnboardingProgressStore.saveLanguageSelection(selection)
        var asrSettings = VoiceASRSettingsStore.load()
        asrSettings.languageHint = selection.asrLanguageHint
        VoiceASRSettingsStore.save(asrSettings)
        statusMessage = "Language preference saved as \(VoiceLanguageModePresentation.title(for: selection.asrLanguageHint))."
    }
}

private struct VoiceTryItStepView: View {
    let controller: AppController
    let markSucceeded: () -> Void
    @State private var text = ""
    @State private var statusMessage = "Click inside the editor, then use the shortcut or buttons to dictate."
    @State private var canConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try it now")
                .font(.title)
                .bold()
            Text("Suggested phrase: 嗨 mingjie, 我们今天 deploy 这个 service 到 production")
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            HStack {
                MAYNButton("Start recording", role: .primary) {
                    canConfirm = false
                    Task { await controller.voiceCoordinator.startRecording() }
                }
                .disabled(controller.voiceCoordinator.state != .idle)
                MAYNButton("Stop and insert") {
                    Task {
                        await controller.voiceCoordinator.stopRecordingAndPaste()
                        if controller.voiceCoordinator.lastTranscript != nil {
                            canConfirm = true
                            statusMessage = "Transcript completed. Confirm it worked to continue."
                        } else {
                            statusMessage = "No transcript was produced. Try again or check microphone/model status."
                        }
                    }
                }
                .disabled(controller.voiceCoordinator.state != .recording)
                MAYNButton("Open Notes") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
                }
                MAYNButton("It works!", role: .primary) {
                    markSucceeded()
                    statusMessage = "Confirmed. You can continue."
                }
                .disabled(!canConfirm)
            }
            if let transcript = controller.voiceCoordinator.lastTranscript {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw ASR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcript.rawText)
                        .foregroundStyle(.secondary)
                    Text("Cleaned text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcript.cleanedText)
                        .fontWeight(.semibold)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .onChange(of: controller.voiceCoordinator.lastTranscript) { _, transcript in
            guard transcript != nil else {
                canConfirm = false
                return
            }
            canConfirm = true
            statusMessage = "Transcript completed. Confirm it worked to continue."
        }
    }
}

private struct VoiceDoneStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(.primary)
            Text("All set")
                .font(.largeTitle)
                .bold()
            Text("Press your voice shortcut anywhere on your Mac to dictate.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Advanced features like per-app prompts, dictionary, and AI cleanup live in Voice Settings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private func openSystemSettings(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
}

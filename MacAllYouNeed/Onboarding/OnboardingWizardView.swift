import AppKit
import FeatureCore
import SwiftUI

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState
    @State private var selectedIDs: [FeatureID]
    @State private var deferredPermissions: Set<Permission> = DeferredPermissionsStore.load()
    @State private var coordinator: FeatureSetupCoordinator?
    @State private var voiceStep: VoiceOnboardingStep = .welcome
    @State private var voiceTryItSucceeded = false
    @State private var featureTryItSucceeded = false
    @State private var voiceRevisitMode = false
    @State private var hasStartedFeatureSetup: Bool

    private let selectionStore: OnboardingSelectionStore

    init(controller: AppController) {
        self.controller = controller
        let store = OnboardingSelectionStore()
        self.selectionStore = store

        let loaded = controller.onboarding
        let initial: OnboardingState
        if loaded == .notStarted {
            initial = .welcome
        } else {
            initial = Self.normalized(loaded)
        }
        _step = State(initialValue: initial)
        _selectedIDs = State(initialValue: store.selectedIDs)
        _hasStartedFeatureSetup = State(initialValue: Self.initiallyStartedFeatureSetup(initial))
    }

    private static func initiallyStartedFeatureSetup(_ state: OnboardingState) -> Bool {
        switch state {
        case .notStarted, .welcome, .featurePicker:
            return false
        default:
            return true
        }
    }

    private var showFeatureStepsInSidebar: Bool {
        if hasStartedFeatureSetup { return true }
        switch step {
        case .notStarted, .welcome, .featurePicker:
            return false
        default:
            return true
        }
    }

    private var registry: FeatureRegistry { controller.runtime.registry }
    private var registryOrder: [FeatureID] { registry.descriptors.map(\.id) }
    private var pickerOrder: [FeatureID] { OnboardingFeaturePickerOrdering.featureIDs }

    var body: some View {
        SetupWizardShell(
            title: "Mac All You Need",
            subtitle: "Initial setup",
            steps: stepDescriptors,
            currentStep: currentSidebarItem,
            onSelectStep: navigateToSidebarItem,
            canGoBack: canGoBack,
            backTitle: backTitle,
            canSkip: canSkip,
            primaryTitle: primaryTitle,
            canAdvance: canAdvance,
            back: back,
            skip: handleSkip,
            primaryAction: handlePrimary
        ) {
            content
        }
        .frame(width: 920, height: 640)
        .onAppear {
            if case .featureSetup(.voice) = step {
                prepareVoiceSetup()
            } else if case .featureSetup(let id) = step, coordinator == nil {
                coordinator = makeCoordinator(for: id)
            }
            setStep(step)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .notStarted, .welcome, .featurePicker:
            FeaturePickerView(registry: registry, selectedIDs: $selectedIDs)
        case .featureSetup(let id):
            if id == .voice {
                VoiceOnboardingEmbeddedView(
                    controller: controller,
                    step: $voiceStep,
                    tryItSucceeded: $voiceTryItSucceeded
                )
            } else if let coordinator, coordinator.descriptor.id == id {
                FeatureSetupContainerView(
                    coordinator: coordinator,
                    showsFeatureHeader: false,
                    tryItSucceeded: $featureTryItSucceeded
                ) {
                    FeatureOnboardingProgressStore.markCompleted(id)
                    selectionStore.markCompleted(id)
                    advanceToNextFeatureOrDone()
                }
                .id(id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .onAppear { coordinator = makeCoordinator(for: id) }
            }
        case .unifiedPermissions:
            UnifiedPermissionsView(
                registry: registry,
                selectedIDs: selectedIDs,
                deferredPermissions: $deferredPermissions
            )
        case .done:
            OnboardingDoneView(
                enabledIDs: selectedIDs,
                deferredPermissions: deferredPermissions,
                onDone: { setStep(.completed) }
            )
        case .completed:
            EmptyView()
        }
    }

    // MARK: - Sidebar

    private var currentSidebarItem: OnboardingSidebarItem {
        OnboardingSidebarBuilder.currentItem(for: step)
    }

    private var stepDescriptors: [SetupStepDescriptor<OnboardingSidebarItem>] {
        OnboardingSidebarBuilder.descriptors(
            step: step,
            selectedIDs: selectedIDs,
            pickerOrder: pickerOrder,
            completedFeatureIDs: selectionStore.completedIDs,
            permissionCount: permissionEntries.count,
            registry: registry,
            voiceStep: voiceStep,
            coordinator: coordinator,
            showFeatureStepsInSidebar: showFeatureStepsInSidebar
        )
    }

    private var permissionEntries: [PermissionUnionEntry] {
        PermissionUnionPlanner.union(for: selectedIDs, registry: registry)
    }

    private func navigateToSidebarItem(_ item: OnboardingSidebarItem) {
        switch item {
        case .features:
            coordinator = nil
            if !selectedIDs.isEmpty {
                hasStartedFeatureSetup = true
            }
            advanceTo(.welcome)
        case .setupOverview:
            break
        case .feature(let id):
            advanceTo(
                .featureSetup(id),
                isRevisit: OnboardingNavigationPlanner.isRevisit(
                    featureID: id,
                    completedIDs: selectionStore.completedIDs
                )
            )
        case .permissions:
            advanceTo(.unifiedPermissions)
        case .done:
            advanceTo(.done)
        }
    }

    // MARK: - Navigation state

    private var primaryTitle: String {
        switch step {
        case .notStarted, .welcome, .featurePicker:
            return selectedIDs.isEmpty ? "Continue with no features" : "Continue"
        case .featureSetup(let id):
            if id == .voice {
                return VoiceOnboardingFlowHelpers.primaryTitle(for: voiceStep)
            }
            return "Continue"
        case .unifiedPermissions:
            return "Continue"
        case .done, .completed:
            return "Done"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .featureSetup(let id):
            if id == .voice {
                return VoiceOnboardingFlowHelpers.canAdvance(
                    step: voiceStep,
                    tryItSucceeded: voiceTryItSucceeded
                )
            }
            guard let coord = coordinator else { return false }
            switch coord.subStep {
            case .config:
                return true
            case .complete:
                return true
            case .download(let progress):
                return progress >= 1
            case .downloadFailed, .idle:
                return false
            }
        default:
            return true
        }
    }

    private var canGoBack: Bool {
        switch step {
        case .notStarted, .welcome, .featurePicker, .completed:
            return false
        case .featureSetup, .unifiedPermissions, .done:
            return true
        }
    }

    private var backTitle: String {
        OnboardingNavigationPlanner.backTitle(
            from: step,
            selectedIDs: selectedIDs,
            pickerOrder: pickerOrder,
            registry: registry
        )
    }

    private var canSkip: Bool {
        switch step {
        case .welcome, .featurePicker, .featureSetup, .unifiedPermissions:
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    private func handlePrimary() {
        switch step {
        case .notStarted, .welcome, .featurePicker:
            if hasStartedFeatureSetup {
                resumeFeatureSetupAfterPickerReturn()
            } else {
                beginFeatureSetupFromScratch()
            }
        case .featureSetup(let id):
            if id == .voice {
                handleVoicePrimary()
                return
            }
            coordinator?.markConfigDone()
            FeatureOnboardingProgressStore.markCompleted(id)
            selectionStore.markCompleted(id)
            advanceToNextFeatureOrDone()
        case .unifiedPermissions:
            DeferredPermissionsStore.save(deferredPermissions)
            advanceTo(.done)
        case .done, .completed:
            setStep(.completed)
        }
    }

    private func handleSkip() {
        switch step {
        case .welcome, .featurePicker:
            selectedIDs = []
            selectionStore.clear()
            DeferredPermissionsStore.reset()
            hasStartedFeatureSetup = false
            setStep(.completed)
        case .featureSetup(let id):
            if id == .voice, voiceStep.canSkip {
                VoiceOnboardingFlowHelpers.skipCurrentStep(
                    step: &voiceStep,
                    tryItSucceeded: &voiceTryItSucceeded,
                    controller: controller
                )
                return
            }
            if let idx = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: idx) }
            FeatureOnboardingProgressStore.markCompleted(id)
            selectionStore.markCompleted(id)
            selectionStore.setSelection(selectedIDs)
            advanceToNextFeatureOrDone()
        case .unifiedPermissions:
            DeferredPermissionsStore.save(deferredPermissions)
            advanceTo(.done)
        default:
            break
        }
    }

    private func back() {
        switch step {
        case .featureSetup(let id):
            if id == .voice {
                if voiceRevisitMode, voiceStep == .done {
                    // Fall through to previous feature.
                } else if VoiceOnboardingFlowHelpers.moveBack(step: &voiceStep, tryItSucceeded: &voiceTryItSucceeded) {
                    return
                }
            }
            if let previous = previousSetupID(before: id) {
                advanceTo(
                    .featureSetup(previous),
                    isRevisit: OnboardingNavigationPlanner.isRevisit(
                        featureID: previous,
                        completedIDs: selectionStore.completedIDs
                    )
                )
            } else {
                if !selectedIDs.isEmpty {
                    hasStartedFeatureSetup = true
                }
                advanceTo(.welcome)
            }
        case .unifiedPermissions:
            advanceToNextFeatureOrDone(fromPermissionsBack: true)
        case .done:
            if permissionEntries.isEmpty {
                advanceToNextFeatureOrDone(fromPermissionsBack: true)
            } else {
                advanceTo(.unifiedPermissions)
            }
        default:
            break
        }
    }

    /// First Continue from the feature picker starts the per-feature setup loop from scratch.
    private func beginFeatureSetupFromScratch() {
        hasStartedFeatureSetup = true
        selectionStore.setSelection(selectedIDs)
        selectionStore.resetCompletedProgress()
        for id in selectedIDs {
            FeatureOnboardingProgressStore.reset(id)
        }
        coordinator = nil
        voiceStep = .welcome
        voiceTryItSucceeded = false
        featureTryItSucceeded = false
        voiceRevisitMode = false

        if let first = selectionStore.firstSelectedID(in: pickerOrder) {
            advanceTo(.featureSetup(first))
        } else if permissionEntries.isEmpty {
            advanceTo(.done)
        } else {
            advanceTo(.unifiedPermissions)
        }
    }

    /// Continue after returning to the picker mid-setup keeps progress and resumes the next step.
    private func resumeFeatureSetupAfterPickerReturn() {
        hasStartedFeatureSetup = true
        syncSelectionStore()
        coordinator = nil
        voiceTryItSucceeded = false
        featureTryItSucceeded = false
        voiceRevisitMode = false

        if let next = selectionStore.nextPendingID(in: pickerOrder) {
            advanceTo(.featureSetup(next))
        } else if permissionEntries.isEmpty {
            advanceTo(.done)
        } else {
            advanceTo(.unifiedPermissions)
        }
    }

    private func advanceToNextFeatureOrDone(fromPermissionsBack: Bool = false) {
        syncSelectionStore()

        if fromPermissionsBack {
            coordinator = nil
            if let last = pickerOrder.filter({ selectedIDs.contains($0) }).last {
                advanceTo(.featureSetup(last))
            } else {
                advanceTo(.welcome)
            }
            return
        }

        coordinator = nil
        if let next = selectionStore.nextPendingID(in: pickerOrder) {
            advanceTo(.featureSetup(next))
        } else if permissionEntries.isEmpty {
            advanceTo(.done)
        } else {
            advanceTo(.unifiedPermissions)
        }
    }

    private func advanceTo(_ newStep: OnboardingState, isRevisit: Bool = false) {
        featureTryItSucceeded = false
        if case .featureSetup = newStep {
            hasStartedFeatureSetup = true
        }
        if case .welcome = newStep {
            syncSelectionStore()
        }
        if case .featureSetup(let id) = newStep {
            if id == .voice {
                coordinator = nil
                prepareVoiceSetup(revisit: isRevisit)
            } else {
                let coord = makeCoordinator(for: id)
                if isRevisit {
                    coord?.prepareForRevisit()
                }
                coordinator = coord
            }
        } else {
            coordinator = nil
            voiceRevisitMode = false
        }
        setStep(newStep)
    }

    private func prepareVoiceSetup(revisit: Bool = false) {
        let progress = VoiceOnboardingProgressStore.load()
        voiceRevisitMode = revisit && progress.isCompleted
        if voiceRevisitMode {
            voiceStep = .done
        } else if progress.isCompleted {
            voiceStep = .welcome
        } else {
            voiceStep = progress.currentStep
        }
        voiceTryItSucceeded = false
    }

    private func handleVoicePrimary() {
        if voiceStep == .done {
            finishVoiceSetup()
            return
        }
        guard voiceStep.next != nil else {
            finishVoiceSetup()
            return
        }
        VoiceOnboardingFlowHelpers.advance(step: &voiceStep, tryItSucceeded: &voiceTryItSucceeded)
    }

    private func finishVoiceSetup() {
        VoiceOnboardingProgressStore.markCompleted()
        FeatureOnboardingProgressStore.markCompleted(.voice)
        selectionStore.markCompleted(.voice)
        advanceToNextFeatureOrDone()
    }

    private func setStep(_ newValue: OnboardingState) {
        step = newValue
        controller.setOnboarding(newValue)
        if newValue == .completed {
            let selected = Set(selectedIDs)
            let registry = registryOrder
            selectionStore.setSelection(selectedIDs)
            NSApplication.shared.keyWindow?.close()
            Task { @MainActor in
                for id in registry {
                    if selected.contains(id) {
                        try? await controller.runtime.applyTransition(.enable, for: id)
                    } else if id != .clipboardSmartText {
                        try? await controller.runtime.applyTransition(.disable, for: id)
                    }
                }
                selectionStore.clear()
            }
        }
    }

    private func previousSetupID(before id: FeatureID) -> FeatureID? {
        OnboardingNavigationPlanner.previousFeatureID(
            before: id,
            selectedIDs: selectedIDs,
            pickerOrder: pickerOrder
        )
    }

    private func syncSelectionStore() {
        selectionStore.setSelection(selectedIDs)
    }

    private func makeCoordinator(for id: FeatureID) -> FeatureSetupCoordinator? {
        guard let descriptor = registry.descriptor(for: id) else { return nil }
        let augmented = FeatureOnboardingWizardRegistry.augmented(descriptor, controller: controller)
        return FeatureSetupCoordinator(
            descriptor: augmented,
            installer: OnboardingInstaller(packInstallController: controller.packInstallController)
        )
    }

    /// Maps legacy install flows onto the current model.
    private static func normalized(_ state: OnboardingState) -> OnboardingState {
        switch state {
        case .featurePicker:
            return .welcome
        case .notStarted:
            return .welcome
        default:
            return state
        }
    }
}

// MARK: - Shared wizard chrome (used by onboarding step views)

enum SetupSidebarRowStyle {
    case standard
    case compactStep
}

struct SetupStepDescriptor<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let subtitle: String
    let symbol: String
    let isCompleted: Bool
    var showsDividerAfter = false
    var rowStyle: SetupSidebarRowStyle = .standard
    var stepNumber: Int?
    var isNavigable = false
}

struct SetupWizardShell<StepID: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let steps: [SetupStepDescriptor<StepID>]
    let currentStep: StepID
    var onSelectStep: ((StepID) -> Void)?
    let canGoBack: Bool
    var backTitle: String = "Back"
    let canSkip: Bool
    let primaryTitle: String
    let canAdvance: Bool
    let back: () -> Void
    let skip: () -> Void
    let primaryAction: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: 540, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 26)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(MAYNTheme.divider)
                    .frame(height: 1)
                actionBar
            }
        }
        .background(MAYNTheme.window)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: descriptorSpacing) {
                    ForEach(steps) { descriptor in
                        SetupProgressRow(
                            descriptor: descriptor,
                            isCurrent: descriptor.id == currentStep,
                            onSelect: descriptor.isNavigable ? { onSelectStep?(descriptor.id) } : nil
                        )
                        if descriptor.showsDividerAfter {
                            sidebarSectionDivider
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 248, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(MAYNTheme.panel)
    }

    private var descriptorSpacing: CGFloat {
        steps.contains(where: { $0.rowStyle == .compactStep }) ? 2 : 4
    }

    private var sidebarSectionDivider: some View {
        Rectangle()
            .fill(MAYNTheme.divider)
            .frame(height: 1)
            .padding(.vertical, 6)
            .padding(.leading, 4)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            MAYNButton(backTitle, action: back)
                .disabled(!canGoBack)
            if canSkip {
                MAYNButton("Skip for now", action: skip)
            }
            Spacer()
            MAYNButton(primaryTitle, role: .primary, action: primaryAction)
                .keyboardShortcut(.return)
                .disabled(!canAdvance)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(MAYNTheme.panel)
    }
}

private struct SetupProgressRow<StepID: Hashable>: View {
    let descriptor: SetupStepDescriptor<StepID>
    let isCurrent: Bool
    var onSelect: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        Group {
            if let onSelect {
                Button(action: onSelect) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch descriptor.rowStyle {
        case .standard:
            standardRow
        case .compactStep:
            compactStepRow
        }
    }

    private var standardRow: some View {
        HStack(alignment: .top, spacing: 10) {
            stepBadge(diameter: 26, fontSize: 11, showsSymbol: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(labelColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !descriptor.subtitle.isEmpty {
                    Text(descriptor.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .rowChrome(isCurrent: isCurrent, isHovering: isHovering && onSelect != nil, cornerRadius: 8)
    }

    private var compactStepRow: some View {
        HStack(alignment: .center, spacing: 8) {
            stepBadge(diameter: 20, fontSize: 10, showsSymbol: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                if isCurrent, !descriptor.subtitle.isEmpty {
                    Text(descriptor.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .rowChrome(isCurrent: isCurrent, isHovering: isHovering && onSelect != nil, cornerRadius: 6)
    }

    private var labelColor: Color {
        if isCurrent {
            return .primary
        }
        if descriptor.isCompleted {
            return .secondary
        }
        if onSelect != nil {
            return .primary
        }
        return .secondary
    }

    private func stepBadge(diameter: CGFloat, fontSize: CGFloat, showsSymbol: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isCurrent ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
            Circle()
                .stroke(isCurrent ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
            if descriptor.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(MAYNTheme.success)
            } else if let stepNumber = descriptor.stepNumber, !showsSymbol {
                Text("\(stepNumber)")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
            } else {
                Image(systemName: descriptor.symbol)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private extension View {
    func rowChrome(isCurrent: Bool, isHovering: Bool, cornerRadius: CGFloat) -> some View {
        background(
            isCurrent ? MAYNTheme.selected : (isHovering ? MAYNTheme.hover : Color.clear),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            }
        }
    }
}

struct SetupTaskPage<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

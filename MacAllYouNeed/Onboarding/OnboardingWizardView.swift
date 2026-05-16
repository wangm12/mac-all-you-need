import AppKit
import FeatureCore
import SwiftUI

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState
    @State private var selectedIDs: [FeatureID]
    @State private var skippedIDs: [FeatureID] = []
    @State private var coordinator: FeatureSetupCoordinator?

    private let selectionStore: OnboardingSelectionStore

    init(controller: AppController) {
        self.controller = controller
        let store = OnboardingSelectionStore()
        self.selectionStore = store

        let loaded = controller.onboarding
        let initial: OnboardingState = (loaded == .notStarted) ? .welcome : loaded
        _step = State(initialValue: initial)
        _selectedIDs = State(initialValue: store.selectedIDs)
    }

    private var registry: FeatureRegistry { controller.runtime.registry }
    private var registryOrder: [FeatureID] { registry.descriptors.map(\.id) }

    var body: some View {
        SetupWizardShell(
            title: "Mac All You Need",
            subtitle: "Initial setup",
            steps: stepDescriptors,
            currentStep: sidebarStep,
            canGoBack: canGoBack,
            canSkip: canSkip,
            primaryTitle: primaryTitle,
            canAdvance: canAdvance,
            back: back,
            skip: handleSkip,
            primaryAction: handlePrimary
        ) {
            content
        }
        .frame(width: 760, height: 520)
        .onAppear { setStep(step) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .notStarted, .welcome:
            WelcomeStep(next: { advanceTo(.featurePicker) })
        case .featurePicker:
            FeaturePickerView(
                registry: registry,
                selectedIDs: $selectedIDs,
                onContinue: handlePrimary,
                onSkip: handleSkip
            )
        case .featureSetup(let id):
            if let coordinator, coordinator.descriptor.id == id {
                FeatureSetupContainerView(coordinator: coordinator) {
                    selectionStore.markCompleted(id)
                    advanceToNextFeatureOrDone()
                }
            } else {
                ProgressView().onAppear {
                    coordinator = makeCoordinator(for: id)
                }
            }
        case .done:
            OnboardingDoneView(
                registry: registry,
                installedIDs: selectedIDs,
                skippedIDs: skippedIDs,
                onDone: { setStep(.completed) }
            )
        case .completed:
            EmptyView()
        }
    }

    // MARK: - Sidebar

    private var stepDescriptors: [SetupStepDescriptor<OnboardingSidebarStep>] {
        OnboardingSidebarStep.allCases.enumerated().map { idx, candidate in
            SetupStepDescriptor(
                id: candidate,
                title: candidate.title,
                subtitle: candidate.subtitle,
                symbol: candidate.symbol,
                isCompleted: idx < currentSidebarIndex
            )
        }
    }

    private var sidebarStep: OnboardingSidebarStep { OnboardingSidebarStep.from(step) }
    private var currentSidebarIndex: Int {
        OnboardingSidebarStep.allCases.firstIndex(of: sidebarStep) ?? 0
    }

    // MARK: - Navigation state

    private var primaryTitle: String {
        switch step {
        case .notStarted, .welcome: return "Get Started"
        case .featurePicker: return selectedIDs.isEmpty ? "Continue with no features" : "Continue"
        case .featureSetup: return "Continue"
        case .done, .completed: return "Done"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .featureSetup:
            guard let coord = coordinator else { return false }
            return coord.subStep == .complete || coord.subStep == .config
        default:
            return true
        }
    }

    private var canGoBack: Bool {
        switch step {
        case .notStarted, .welcome, .completed: return false
        default: return true
        }
    }

    private var canSkip: Bool {
        switch step {
        case .featurePicker: return true
        case .featureSetup: return true   // skip just this feature
        default: return false
        }
    }

    // MARK: - Actions

    private func handlePrimary() {
        switch step {
        case .notStarted, .welcome:
            advanceTo(.featurePicker)
        case .featurePicker:
            selectionStore.setSelection(selectedIDs)
            skippedIDs = registryOrder.filter { !selectedIDs.contains($0) }
            advanceToNextFeatureOrDone()
        case .featureSetup(let id):
            coordinator?.markConfigDone()
            selectionStore.markCompleted(id)
            advanceToNextFeatureOrDone()
        case .done, .completed:
            setStep(.completed)
        }
    }

    private func handleSkip() {
        switch step {
        case .featurePicker:
            // "Skip for now" → exit with zero features enabled.
            selectedIDs = []
            skippedIDs = registryOrder
            selectionStore.clear()
            setStep(.completed)
        case .featureSetup(let id):
            // Skip this feature; keep it in skippedIDs.
            if let idx = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: idx) }
            if !skippedIDs.contains(id) { skippedIDs.append(id) }
            selectionStore.markCompleted(id)   // treat as "done" so nextPendingID skips it
            advanceToNextFeatureOrDone()
        default:
            break
        }
    }

    private func back() {
        switch step {
        case .featurePicker:
            advanceTo(.welcome)
        case .featureSetup:
            advanceTo(.featurePicker)
        case .done:
            if let last = selectedIDs.last { advanceTo(.featureSetup(last)) }
            else { advanceTo(.featurePicker) }
        default:
            break
        }
    }

    private func advanceToNextFeatureOrDone() {
        coordinator = nil
        if let next = selectionStore.nextPendingID(in: registryOrder) {
            advanceTo(.featureSetup(next))
        } else {
            advanceTo(.done)
        }
    }

    private func advanceTo(_ newStep: OnboardingState) {
        if case .featureSetup(let id) = newStep {
            coordinator = makeCoordinator(for: id)
        }
        setStep(newStep)
    }

    private func setStep(_ newValue: OnboardingState) {
        step = newValue
        controller.setOnboarding(newValue)
        if newValue == .completed {
            selectionStore.clear()
            Task { @MainActor in
                for id in selectedIDs {
                    try? await controller.runtime.applyTransition(.enable, for: id)
                }
                NSApplication.shared.keyWindow?.close()
            }
        }
    }

    private func makeCoordinator(for id: FeatureID) -> FeatureSetupCoordinator? {
        guard let descriptor = registry.descriptor(for: id) else { return nil }
        // Augment the descriptor with a Voice config factory if not already set.
        // VoiceDescriptor is built without a controller reference (AppController isn't
        // available when the registry is first constructed), so we wire it here where
        // the wizard already holds the controller.
        let augmented = augmented(descriptor)
        return FeatureSetupCoordinator(
            descriptor: augmented,
            installer: OnboardingInstaller(packInstallController: controller.packInstallController)
        )
    }

    /// Returns the descriptor with `onboardingSetupFactory` wired if the registry didn't
    /// supply one (e.g. VoiceDescriptor which needs the controller reference).
    private func augmented(_ descriptor: FeatureDescriptor) -> FeatureDescriptor {
        guard descriptor.onboardingSetupFactory == nil else { return descriptor }
        guard descriptor.id == .voice else { return descriptor }
        let c = controller
        return FeatureDescriptor(
            id: descriptor.id,
            displayName: descriptor.displayName,
            icon: descriptor.icon,
            summary: descriptor.summary,
            detailDescription: descriptor.detailDescription,
            requiredPermissions: descriptor.requiredPermissions,
            assetPacks: descriptor.assetPacks,
            assetCaches: descriptor.assetCaches,
            hotkeys: descriptor.hotkeys,
            osExtensionPolicy: descriptor.osExtensionPolicy,
            activator: descriptor.activator,
            settingsTabFactory: descriptor.settingsTabFactory,
            onboardingSetupFactory: { @Sendable @MainActor in
                AnyView(VoiceProviderSetupView(controller: c))
            },
            menuBarItemFactory: descriptor.menuBarItemFactory
        )
    }
}

/// Sidebar navigation model. The actual flow has many states (one per feature in
/// `.featureSetup`); the sidebar collapses them into four high-level phases.
enum OnboardingSidebarStep: Hashable, CaseIterable {
    case welcome, picker, setup, done

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .picker: return "Choose Features"
        case .setup: return "Set Up"
        case .done: return "Done"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "What this app does"
        case .picker: return "Pick what you want"
        case .setup: return "Per-feature config"
        case .done: return "Start using it"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "sparkles"
        case .picker: return "square.grid.2x2"
        case .setup: return "gearshape"
        case .done: return "checkmark"
        }
    }

    static func from(_ state: OnboardingState) -> OnboardingSidebarStep {
        switch state {
        case .notStarted, .welcome: return .welcome
        case .featurePicker: return .picker
        case .featureSetup: return .setup
        case .done, .completed: return .done
        }
    }
}

// MARK: - Shared wizard chrome (used by onboarding step views)

struct SetupStepDescriptor<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let subtitle: String
    let symbol: String
    let isCompleted: Bool
}

struct SetupWizardShell<StepID: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let steps: [SetupStepDescriptor<StepID>]
    let currentStep: StepID
    let canGoBack: Bool
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
                        .frame(maxWidth: 460, alignment: .topLeading)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 30)
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
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { descriptor in
                    SetupProgressRow(
                        descriptor: descriptor,
                        isCurrent: descriptor.id == currentStep
                    )
                }
            }

            Spacer()
        }
        .frame(width: 220, alignment: .topLeading)
        .padding(22)
        .background(MAYNTheme.panel)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            MAYNButton("Back", action: back)
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.isCompleted ? "checkmark.circle.fill" : descriptor.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isCurrent ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                )
                .overlay(Circle().stroke(isCurrent ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                Text(descriptor.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isCurrent ? MAYNTheme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

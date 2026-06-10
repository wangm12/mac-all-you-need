import FeatureCore
import Foundation

/// Sidebar identity for the app-install onboarding wizard.
enum OnboardingSidebarItem: Hashable {
    case features
    case setupOverview
    case feature(FeatureID)
    case permissions
    case done
}

enum OnboardingSidebarBuilder {
    @MainActor
    static func descriptors(
        step: OnboardingState,
        selectedIDs: [FeatureID],
        pickerOrder: [FeatureID],
        completedFeatureIDs: Set<FeatureID>,
        permissionCount: Int,
        registry: FeatureRegistry,
        voiceStep: VoiceOnboardingStep,
        coordinator: FeatureSetupCoordinator?,
        showFeatureStepsInSidebar: Bool
    ) -> [SetupStepDescriptor<OnboardingSidebarItem>] {
        let selectedInOrder = pickerOrder.filter { selectedIDs.contains($0) }
        let pastPicker = showFeatureStepsInSidebar

        var items: [SetupStepDescriptor<OnboardingSidebarItem>] = []

        items.append(
            SetupStepDescriptor(
                id: .features,
                title: "Choose Features",
                subtitle: pastPicker ? "" : "Pick what you want",
                symbol: "square.grid.2x2",
                isCompleted: pastPicker,
                showsDividerAfter: pastPicker && !selectedInOrder.isEmpty,
                isNavigable: isNavigable(
                    .features,
                    step: step,
                    selectedInOrder: selectedInOrder,
                    completedFeatureIDs: completedFeatureIDs,
                    showFeatureStepsInSidebar: showFeatureStepsInSidebar
                )
            )
        )

        if pastPicker {
            for (index, id) in selectedInOrder.enumerated() {
                let descriptor = registry.descriptor(for: id)
                let isCurrent = isCurrentFeature(id, step: step)
                items.append(
                    SetupStepDescriptor(
                        id: .feature(id),
                        title: descriptor?.displayName ?? id.rawValue,
                        subtitle: compactFeatureSubtitle(
                            id: id,
                            step: step,
                            completedFeatureIDs: completedFeatureIDs,
                            selectedInOrder: selectedInOrder,
                            voiceStep: voiceStep,
                            coordinator: coordinator,
                            isCurrent: isCurrent
                        ),
                        symbol: descriptor?.icon ?? "gearshape",
                        isCompleted: isFeatureCompleted(
                            id,
                            step: step,
                            completedFeatureIDs: completedFeatureIDs,
                            selectedInOrder: selectedInOrder
                        ),
                        rowStyle: .compactStep,
                        stepNumber: index + 1,
                        isNavigable: isNavigable(
                            .feature(id),
                            step: step,
                            selectedInOrder: selectedInOrder,
                            completedFeatureIDs: completedFeatureIDs,
                            showFeatureStepsInSidebar: showFeatureStepsInSidebar
                        )
                    )
                )
            }
        } else {
            items.append(
                SetupStepDescriptor(
                    id: .setupOverview,
                    title: "Set Up",
                    subtitle: selectedInOrder.isEmpty ? "Per-feature guides" : "\(selectedInOrder.count) features selected",
                    symbol: "gearshape",
                    isCompleted: false,
                    isNavigable: false
                )
            )
        }

        if permissionCount > 0 {
            if var last = items.last {
                last.showsDividerAfter = true
                items[items.count - 1] = last
            }
            items.append(
                SetupStepDescriptor(
                    id: .permissions,
                    title: "Permissions",
                    subtitle: pastPicker ? "" : "System access",
                    symbol: "lock.shield",
                    isCompleted: isPastPermissions(step),
                    isNavigable: isNavigable(
                        .permissions,
                        step: step,
                        selectedInOrder: selectedInOrder,
                        completedFeatureIDs: completedFeatureIDs,
                        showFeatureStepsInSidebar: showFeatureStepsInSidebar
                    )
                )
            )
        }

        items.append(
            SetupStepDescriptor(
                id: .done,
                title: "Done",
                subtitle: pastPicker ? "" : "Start using it",
                symbol: "checkmark",
                isCompleted: step == .completed,
                isNavigable: isNavigable(
                    .done,
                    step: step,
                    selectedInOrder: selectedInOrder,
                    completedFeatureIDs: completedFeatureIDs,
                    showFeatureStepsInSidebar: showFeatureStepsInSidebar
                )
            )
        )

        return items
    }

    static func currentItem(for step: OnboardingState) -> OnboardingSidebarItem {
        switch step {
        case .notStarted, .welcome, .featurePicker:
            return .features
        case .featureSetup(let id):
            return .feature(id)
        case .unifiedPermissions:
            return .permissions
        case .done, .completed:
            return .done
        }
    }

    private static func isPastPermissions(_ step: OnboardingState) -> Bool {
        switch step {
        case .done, .completed:
            return true
        default:
            return false
        }
    }

    private static func isCurrentFeature(_ id: FeatureID, step: OnboardingState) -> Bool {
        guard case .featureSetup(let current) = step else { return false }
        return current == id
    }

    private static func isNavigable(
        _ item: OnboardingSidebarItem,
        step: OnboardingState,
        selectedInOrder: [FeatureID],
        completedFeatureIDs: Set<FeatureID>,
        showFeatureStepsInSidebar: Bool
    ) -> Bool {
        switch item {
        case .features:
            return showFeatureStepsInSidebar
        case .setupOverview:
            return false
        case .feature(let id):
            guard showFeatureStepsInSidebar else { return false }
            if isCurrentFeature(id, step: step) { return false }
            return isFeatureCompleted(
                id,
                step: step,
                completedFeatureIDs: completedFeatureIDs,
                selectedInOrder: selectedInOrder
            )
        case .permissions:
            switch step {
            case .unifiedPermissions:
                return false
            case .done, .completed:
                return true
            default:
                return false
            }
        case .done:
            switch step {
            case .done:
                return false
            case .completed:
                return true
            default:
                return false
            }
        }
    }

    private static func isFeatureCompleted(
        _ id: FeatureID,
        step: OnboardingState,
        completedFeatureIDs: Set<FeatureID>,
        selectedInOrder: [FeatureID]
    ) -> Bool {
        if completedFeatureIDs.contains(id) { return true }
        guard case .featureSetup(let current) = step else {
            switch step {
            case .unifiedPermissions, .done, .completed:
                return selectedInOrder.contains(id)
            default:
                return false
            }
        }
        guard let currentIndex = selectedInOrder.firstIndex(of: current),
              let featureIndex = selectedInOrder.firstIndex(of: id) else {
            return false
        }
        return featureIndex < currentIndex
    }

    @MainActor
    private static func compactFeatureSubtitle(
        id: FeatureID,
        step: OnboardingState,
        completedFeatureIDs: Set<FeatureID>,
        selectedInOrder: [FeatureID],
        voiceStep: VoiceOnboardingStep,
        coordinator: FeatureSetupCoordinator?,
        isCurrent: Bool
    ) -> String {
        guard isCurrent else { return "" }

        if id == .voice {
            let index = VoiceOnboardingStep.orderedCases.firstIndex(of: voiceStep) ?? 0
            return "Step \(index + 1) of \(VoiceOnboardingStep.orderedCases.count) · \(voiceStep.title)"
        }

        if let coordinator, coordinator.descriptor.id == id {
            switch coordinator.subStep {
            case .idle:
                return "Preparing…"
            case .download:
                return "Downloading…"
            case .downloadFailed:
                return "Install failed"
            case .config:
                return "Configure"
            case .complete:
                return ""
            }
        }

        return ""
    }
}

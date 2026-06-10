import Core
import Platform
import SwiftUI

/// Clipboard feature onboarding: preview → shortcut → Smart Text → privacy.
struct ClipboardOnboardingHotkeySection: View {
    let controller: AppController
    @State private var hotkeyMap = HotkeyMapStore.load()
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var tryStatus: String?

    private var clipboardDescriptor: Platform.HotkeyDescriptor {
        let defaultDescriptor = HotkeyAction.clipboard.primaryDefaultDescriptor ?? .defaultClipboard
        return hotkeyMap[.clipboard]?.first ?? defaultDescriptor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingGroupedSection(
                title: "Preview",
                subtitle: "The clipboard dock rises from the bottom of your screen."
            ) {
                OnboardingLoopingMediaView(
                    resourceName: "clipboard-dock-demo",
                    resourceExtension: "mp4",
                    accessibilityLabel: "Clipboard dock demo"
                ) {
                    ClipboardDockOnboardingPreview()
                }
            }

            OnboardingGroupedSection(
                title: "Shortcut",
                subtitle: "Press this in any app to open the dock."
            ) {
                OnboardingPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        HotkeyRecorderControl(
                            descriptor: hotkeyBinding,
                            issueMessage: hotkeyIssueMessage,
                            candidateIssueMessage: hotkeyCandidateIssueMessage,
                            defaultDescriptor: HotkeyAction.clipboard.primaryDefaultDescriptor,
                            recorderWidth: 140,
                            errorWidth: 300,
                            alignment: .leading,
                            errorFrameAlignment: .leading,
                            reset: {
                                if let descriptor = HotkeyAction.clipboard.primaryDefaultDescriptor {
                                    setHotkey(descriptor)
                                }
                            }
                        )

                        HStack(spacing: 8) {
                            MAYNButton("Open dock now", role: .primary) {
                                controller.clipboardDock.toggle()
                                tryStatus = "If the dock appeared at the bottom of your screen, you're ready."
                            }
                            MAYNButton("Use default") {
                                if let descriptor = HotkeyAction.clipboard.primaryDefaultDescriptor {
                                    setHotkey(descriptor)
                                }
                            }
                        }

                        if let tryStatus {
                            StatusPill(text: tryStatus, kind: .neutral)
                        }
                    }
                }
            }

            OnboardingGroupedSection(
                title: "Smart Text",
                subtitle: "Optional on-device intelligence for clips."
            ) {
                ClipboardSmartTextOnboardingSection(controller: controller)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text("Clipboard history is encrypted and stored locally in your App Group container.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotkeyBinding: Binding<Platform.HotkeyDescriptor> {
        Binding(get: { clipboardDescriptor }, set: { setHotkey($0) })
    }

    private var hotkeyIssueMessage: String? {
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: clipboardDescriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: .clipboard
        )
    }

    private func hotkeyCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func setHotkey(_ descriptor: Platform.HotkeyDescriptor) {
        var descriptors = hotkeyMap[.clipboard] ?? HotkeyAction.clipboard.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[.clipboard] = descriptors
        hotkeyMap = next

        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        ) != nil {
            hotkeyRegistrationErrors = [:]
            return
        }

        do {
            try controller.applyHotkeyMap(next)
            HotkeyMapStore.save(next)
            hotkeyRegistrationErrors = [:]
            tryStatus = "Shortcut updated to \(descriptor.display)."
        } catch {
            hotkeyRegistrationErrors = HotkeyRecorderControlPresentation.registrationErrors(
                from: error,
                changedAction: .clipboard
            )
        }
    }
}

import Core
import Platform
import SwiftUI

/// Finder Folder History intro + hotkey setup for main and Dashboard enable flows.
struct FolderHistoryOnboardingSetupView: View {
    var controller: AppController?
    @Environment(\.onboardingTryItSucceeded) private var tryItSucceeded
    @State private var hotkeyMap = HotkeyMapStore.load()
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var tryStatus: String?

    private var historyDescriptor: Platform.HotkeyDescriptor {
        let defaultDescriptor = HotkeyAction.finderHistory.primaryDefaultDescriptor ?? .defaultFolderHistory
        return hotkeyMap[.finderHistory]?.first ?? defaultDescriptor
    }

    private var store: FolderHistoryStore? { FolderHistoryStoreLocator.shared() }

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Mac All You Need remembers which folders you open in Finder — never what is inside them.",
                "Press your history shortcut in Finder to jump back to a recent path."
            ],
            tryItSubtitle: "Record a Finder folder, then open the history switcher.",
            tryIt: {
            VStack(alignment: .leading, spacing: 14) {
                if controller != nil {
                    hotkeySection
                } else {
                    OnboardingShortcutSection(
                        title: "History shortcut",
                        subtitle: "Customize the shortcut on the Finder History page.",
                        shortcutDisplay: historyDescriptor.display
                    )
                }

                OnboardingTryItPanel(
                    instruction: "1. Open any folder in Finder. 2. Tap Capture now. 3. Press \(historyDescriptor.display) to open the switcher.",
                    statusMessage: tryStatus,
                    statusKind: tryStatus?.contains("Recorded") == true ? .success : .neutral
                ) {
                    HStack(spacing: 10) {
                        MAYNButton("Capture now", role: .primary) {
                            captureCurrentFinderFolder()
                        }
                        MAYNButton("Open Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
                        }
                    }
                }
            }
        },
        footnote: "Excluded paths live on the Enhanced Finder History tab."
        )
    }

    private var hotkeySection: some View {
        OnboardingGroupedSection(title: "History shortcut", subtitle: "Click the field, then press the keys you want.") {
            OnboardingPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HotkeyRecorderControl(
                        descriptor: hotkeyBinding,
                        issueMessage: hotkeyIssueMessage,
                        candidateIssueMessage: hotkeyCandidateIssueMessage,
                        defaultDescriptor: HotkeyAction.finderHistory.primaryDefaultDescriptor,
                        recorderWidth: 132,
                        errorWidth: 280,
                        alignment: .leading,
                        errorFrameAlignment: .leading,
                        reset: {
                            if let descriptor = HotkeyAction.finderHistory.primaryDefaultDescriptor {
                                setHotkey(descriptor)
                            }
                        }
                    )
                    MAYNButton("Use default") {
                        if let descriptor = HotkeyAction.finderHistory.primaryDefaultDescriptor {
                            setHotkey(descriptor)
                        }
                    }
                }
            }
        }
    }

    private func captureCurrentFinderFolder() {
        guard AXIsProcessTrusted() else {
            tryStatus = "Grant Accessibility in Settings → Permissions, then try again."
            return
        }
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.finder" })?
            .processIdentifier
        else {
            tryStatus = "Finder is not running."
            return
        }
        guard let path = FolderHistoryFinderPathResolver.resolve(pid: pid, axReader: SystemFolderHistoryAXReader()) else {
            tryStatus = "Could not read the front Finder folder. Open a folder window first."
            return
        }
        do {
            _ = try store?.upsert(path: path, now: Date())
            OnboardingTryItReporter.markSucceeded(tryItSucceeded)
            tryStatus = "Recorded \(path). Folder history is ready."
        } catch {
            tryStatus = "Could not save: \(error.localizedDescription)"
        }
    }

    private var hotkeyBinding: Binding<Platform.HotkeyDescriptor> {
        Binding(get: { historyDescriptor }, set: { setHotkey($0) })
    }

    private var hotkeyIssueMessage: String? {
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: historyDescriptor,
            action: .finderHistory,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: .finderHistory
        )
    }

    private func hotkeyCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .finderHistory,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func setHotkey(_ descriptor: Platform.HotkeyDescriptor) {
        guard let controller else { return }
        var descriptors = hotkeyMap[.finderHistory] ?? HotkeyAction.finderHistory.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[.finderHistory] = descriptors
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
                changedAction: .finderHistory
            )
        }
    }
}

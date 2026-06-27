import AppKit
import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
final class WindowHubCoordinator {
    private(set) var snapshot: WindowHubSnapshot = .empty
    private(set) var searchQuery = ""
    private(set) var mode: WindowHubPanelMode = .dashboard
    private(set) var selectedTargetID: WindowHubTargetID?
    private(set) var pendingPlan: WindowHubActionPlan?
    private(set) var aiPlan: WindowHubAIPlan?
    private(set) var executionState: WindowHubActionExecutionState = .idle
    private(set) var lastSwitchResult: WindowHubSwitchResult?
    private(set) var isIndexing = false
    private(set) var isAIOrganizing = false
    private(set) var loadingPIDs: Set<pid_t> = []
    private(set) var settings = WindowHubSettingsStore.load()
    private(set) var recentEntries: [WindowHubRecentEntry] = []

    private let actionExecutor = WindowHubActionExecutor()
    private var indexingTask: Task<Void, Never>?
    private var llmGenerate: ((String, String) async throws -> String)?
    private var frontPID: pid_t?
    private var refreshEnumeratedPIDs: Set<pid_t> = []
    private var droppedStaleSections = false
    nonisolated(unsafe) private var terminateObserver: NSObjectProtocol?
    var onDismissForActivation: (() -> Void)?

    init() {
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            WindowHubAXReader.evict(pid: pid)
            WindowHubAXWindowBridge.evict(pid: pid)
            BrowserAppleScriptTabCache.evict(pid: pid)
        }
    }

    deinit {
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
        }
    }

    var filteredTargets: [WindowHubTarget] {
        WindowHubFuzzyMatcher.filter(targets: snapshot.flatTargets, query: searchQuery)
    }

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func isLoading(pid: pid_t) -> Bool {
        loadingPIDs.contains(pid)
    }

    func configureLLM(_ generate: @escaping (String, String) async throws -> String) {
        llmGenerate = generate
    }

    func openPanel() {
        reloadSettings()
        BrowserAppleScriptTabCache.resetTransientFailures()
        recentEntries = WindowHubSnapshotStore.loadRecent()
        mode = .dashboard
        searchQuery = ""
        frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if isAccessibilityGranted, let cached = WindowHubSnapshotCache.load() {
            snapshot = WindowHubSnapshot(
                capturedAt: cached.capturedAt,
                phase: .stale,
                currentTargetID: cached.currentTargetID,
                sections: cached.sections,
                flatTargets: cached.flatTargets,
                timedOutProviders: []
            )
            loadingPIDs = Set(cached.sections.map(\.pid))
        } else {
            if !isAccessibilityGranted {
                WindowHubSnapshotCache.clear()
            }
            snapshot = WindowHubSnapshot(
                capturedAt: Date(),
                phase: .shell,
                currentTargetID: nil,
                sections: [],
                flatTargets: [],
                timedOutProviders: []
            )
            loadingPIDs = []
        }
        refreshIndex()
        syncSelectionToNavigableTargets()
    }

    func closePanel() {
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        loadingPIDs = []
        snapshot = .empty
        pendingPlan = nil
        aiPlan = nil
        mode = .dashboard
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        mode = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .dashboard : .searchResults
        syncSelectionToNavigableTargets()
    }

    var navigableTargets: [WindowHubTarget] {
        switch mode {
        case .searchResults:
            return filteredTargets
        case .dashboard, .actionConfirmation:
            return snapshot.flatTargets
        case .browseColumns:
            return snapshot.flatTargets
        }
    }

    func selectTarget(_ target: WindowHubTarget) {
        selectedTargetID = target.id
    }

    func moveSelection(delta: Int) {
        let targets = navigableTargets
        guard !targets.isEmpty else {
            selectedTargetID = nil
            return
        }
        let currentIndex = selectedTargetID.flatMap { id in
            targets.firstIndex(where: { $0.id == id })
        } ?? -1
        let nextIndex = min(max(0, currentIndex + delta), targets.count - 1)
        selectedTargetID = targets[nextIndex].id
    }

    func activateSelectedTarget() async {
        guard let selectedTargetID,
              let target = navigableTargets.first(where: { $0.id == selectedTargetID })
        else { return }
        await activate(target: target)
    }

    func syncSelectionToNavigableTargets() {
        let targets = navigableTargets
        guard !targets.isEmpty else {
            selectedTargetID = nil
            return
        }
        if let selectedTargetID,
           targets.contains(where: { $0.id == selectedTargetID })
        {
            return
        }
        self.selectedTargetID = targets.first?.id
    }

    func refreshIndex() {
        indexingTask?.cancel()
        reloadSettings()
        isIndexing = true
        let currentSettings = settings
        let streamFrontPID = frontPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        frontPID = streamFrontPID

        indexingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isIndexing = false }

            self.refreshEnumeratedPIDs = []
            self.droppedStaleSections = false

            let built = await WindowHubEnumerator.refresh(settings: currentSettings) { section, streamPhase in
                await self.mergeStreamedSection(section, streamPhase: streamPhase)
            }
            guard !Task.isCancelled else { return }

            self.applyBuiltSnapshot(built, settings: currentSettings)

            if currentSettings.browserTabDiscoveryEnabled {
                await self.runChromiumJXAUpgrade(settings: currentSettings)
            } else {
                self.loadingPIDs = []
            }

            guard !Task.isCancelled else { return }
            self.persistSnapshot()
        }
    }

    func activate(target: WindowHubTarget) async {
        onDismissForActivation?()
        let result = await WindowHubActivationService.activate(target: target, in: snapshot)
        lastSwitchResult = result
        if result == .switched || result == .switchedAppOnly {
            WindowHubSnapshotStore.recordVisit(target)
            recentEntries = WindowHubSnapshotStore.loadRecent()
        }
    }

    func requestDirectAction(_ action: WindowHubDirectAction, target: WindowHubTarget) {
        pendingPlan = WindowHubActionPlanner.plan(action: action, target: target, settings: settings)
        mode = .actionConfirmation
    }

    func confirmPendingPlan() async {
        guard let plan = pendingPlan else { return }
        executionState = await actionExecutor.execute(plan: plan, snapshot: snapshot)
        pendingPlan = nil
        mode = .dashboard
        refreshIndex()
    }

    func dismissPendingPlan() {
        pendingPlan = nil
        mode = .dashboard
    }

    var isAIOrganizePresented: Bool { aiPlan != nil }

    func requestAIOrganize() async {
        isAIOrganizing = true
        defer { isAIOrganizing = false }

        guard let llmGenerate else {
            aiPlan = WindowHubAIPlan(summary: "AI provider is not configured.", steps: [])
            pendingPlan = WindowHubActionPlan(title: "AI Organize", steps: [], requiresConfirmation: true, canUndo: false)
            return
        }
        do {
            let plan = try await WindowHubTabOrganizerLLMService.organize(
                snapshot: snapshot,
                settings: settings,
                generate: llmGenerate
            )
            aiPlan = plan
            pendingPlan = WindowHubTabOrganizerExecutor.executableSteps(from: plan, snapshot: snapshot)
        } catch {
            aiPlan = WindowHubAIPlan(summary: "AI organize failed: \(error.localizedDescription)", steps: [])
            pendingPlan = WindowHubActionPlan(title: "AI Organize", steps: [], requiresConfirmation: true, canUndo: false)
        }
    }

    func confirmAIOrganize(selectedStepIDs: Set<String>) async {
        guard let plan = pendingPlan else { return }
        let steps = plan.steps.filter { selectedStepIDs.contains($0.id) && $0.executable }
        guard !steps.isEmpty else { return }
        let filtered = WindowHubActionPlan(
            title: plan.title,
            steps: steps,
            requiresConfirmation: plan.requiresConfirmation,
            canUndo: plan.canUndo
        )
        executionState = await actionExecutor.execute(plan: filtered, snapshot: snapshot)
        dismissAIOrganize()
        refreshIndex()
    }

    func dismissAIOrganize() {
        aiPlan = nil
        pendingPlan = nil
    }

    func reloadSettings() {
        settings = WindowHubSettingsStore.load()
    }

    func saveSettings(_ newSettings: WindowHubSettings) {
        settings = newSettings
        WindowHubSettingsStore.save(newSettings)
    }

    func showBrowseColumns() {
        mode = .browseColumns
    }

    // MARK: - Private indexing helpers

    private func mergeStreamedSection(_ section: WindowHubAppSection, streamPhase: WindowHubIndexingPhase) {
        refreshEnumeratedPIDs.insert(section.pid)

        var sections = snapshot.sections
        if streamPhase != .shell, !droppedStaleSections {
            sections = sections.filter { refreshEnumeratedPIDs.contains($0.pid) }
            droppedStaleSections = true
        }
        WindowHubSectionMerger.upsert(section, into: &sections)
        sections = WindowHubSectionMerger.sorted(sections, frontPID: frontPID)
        let flatTargets = WindowHubSectionMerger.flatTargets(from: sections)
        if streamPhase != .shell {
            loadingPIDs.remove(section.pid)
        }

        let snapshotPhase: WindowHubIndexingPhase = switch streamPhase {
        case .shell: .shell
        case .complete: .complete
        default: .incremental
        }

        snapshot = WindowHubSnapshot(
            capturedAt: Date(),
            phase: snapshotPhase,
            currentTargetID: snapshot.currentTargetID,
            sections: sections,
            flatTargets: flatTargets,
            timedOutProviders: snapshot.timedOutProviders
        )
    }

    private func applyBuiltSnapshot(_ built: WindowHubSnapshot, settings: WindowHubSettings) {
        snapshot = canonicalSnapshot(from: built)
        loadingPIDs = loadingPIDs.filter { pid in
            NSRunningApplication(processIdentifier: pid) != nil
        }
        loadingPIDs = loadingPIDs.intersection(refreshEnumeratedPIDs)
        reconcileLoadingAfterFullPass(settings: settings)
        syncSelectionToNavigableTargets()
    }

    private func canonicalSnapshot(from built: WindowHubSnapshot) -> WindowHubSnapshot {
        WindowHubSnapshot(
            capturedAt: built.capturedAt,
            phase: built.phase,
            currentTargetID: built.currentTargetID,
            sections: built.sections,
            flatTargets: WindowHubSectionMerger.flatTargets(from: built.sections),
            timedOutProviders: built.timedOutProviders
        )
    }

    private func reconcileLoadingAfterFullPass(settings: WindowHubSettings) {
        loadingPIDs = loadingPIDs.filter { pid in
            NSRunningApplication(processIdentifier: pid) != nil
        }
        guard settings.browserTabDiscoveryEnabled else {
            loadingPIDs = []
            return
        }
        let chromiumPIDs = snapshot.sections.compactMap { section -> pid_t? in
            guard BrowserAppleScriptTabReader.isChromium(section.bundleIdentifier) else { return nil }
            return section.pid
        }
        loadingPIDs = Set(chromiumPIDs)
    }

    private func runChromiumJXAUpgrade(settings: WindowHubSettings) async {
        let chromiumPIDs = snapshot.sections.compactMap { section -> pid_t? in
            guard BrowserAppleScriptTabReader.isChromium(section.bundleIdentifier) else { return nil }
            return section.pid
        }
        guard !chromiumPIDs.isEmpty else {
            loadingPIDs = []
            return
        }

        await WindowHubEnumerator.upgradeChromiumApps(settings: settings, pids: chromiumPIDs) { section, streamPhase in
            await self.mergeStreamedSection(section, streamPhase: streamPhase)
        }

        loadingPIDs = []
        snapshot = canonicalSnapshot(
            from: WindowHubSnapshot(
                capturedAt: Date(),
                phase: .complete,
                currentTargetID: snapshot.currentTargetID,
                sections: snapshot.sections,
                flatTargets: snapshot.flatTargets,
                timedOutProviders: snapshot.timedOutProviders
            )
        )
    }

    private func persistSnapshot() {
        let cached = WindowHubCachedSnapshot(
            capturedAt: snapshot.capturedAt,
            currentTargetID: snapshot.currentTargetID,
            sections: snapshot.sections
        )
        WindowHubSnapshotCache.save(cached)
    }
}

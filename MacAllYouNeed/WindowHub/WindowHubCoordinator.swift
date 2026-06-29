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
    var pendingPlan: WindowHubActionPlan?
    var aiPlan: WindowHubAIPlan?
    var executionState: WindowHubActionExecutionState = .idle
    private(set) var lastSwitchResult: WindowHubSwitchResult?
    private(set) var isIndexing = false
    var isAIOrganizing = false
    var loadingPIDs: Set<pid_t> = []
    private(set) var settings = WindowHubSettingsStore.load()
    private(set) var recentEntries: [WindowHubRecentEntry] = []

    let actionExecutor = WindowHubActionExecutor()
    private var indexingTask: Task<Void, Never>?
    var llmGenerate: ((String, String) async throws -> String)?
    var frontPID: pid_t?
    var refreshEnumeratedPIDs: Set<pid_t> = []
    var droppedStaleSections = false
    private var masonryNavigableTargets: [WindowHubTarget] = []
    private var masonryColumnTargets: [[WindowHubTarget]] = []
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

    var filteredSections: [WindowHubAppSection] {
        WindowHubSectionMerger.filteredSections(from: snapshot.sections, query: searchQuery)
    }

    var frontmostPID: pid_t? {
        frontPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    var currentBreadcrumb: String? {
        guard let currentTargetID = snapshot.currentTargetID else { return nil }
        return snapshot.flatTargets.first(where: { $0.id == currentTargetID })?.breadcrumb
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
        masonryNavigableTargets = []
        masonryColumnTargets = []
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        if mode != .actionConfirmation {
            mode = .dashboard
        }
        syncSelectionToNavigableTargets()
    }

    func clearSearchIfNeeded() -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        searchQuery = ""
        syncSelectionToNavigableTargets()
        return true
    }

    func updateMasonryNavigableTargets(
        _ targets: [WindowHubTarget],
        columnTargets: [[WindowHubTarget]]
    ) {
        masonryNavigableTargets = targets
        masonryColumnTargets = columnTargets
        syncSelectionToNavigableTargets()
    }

    func isSectionPartial(_ section: WindowHubAppSection) -> Bool {
        !snapshot.timedOutProviders.isEmpty
            && section.windowGroups.contains { group in
                group.isHeavy || group.hiddenTabCount > 0
            }
    }

    var navigableTargets: [WindowHubTarget] {
        if !masonryNavigableTargets.isEmpty {
            return masonryNavigableTargets
        }
        return WindowHubSectionMerger.filteredSections(from: snapshot.sections, query: searchQuery)
            .flatMap(\.windowGroups)
            .flatMap(\.visibleTargets)
    }

    func selectTarget(_ target: WindowHubTarget) {
        selectedTargetID = target.id
    }

    func moveSelection(delta: Int) {
        selectedTargetID = WindowHubMasonryNavigation.moveSelection(
            selectedTargetID: selectedTargetID,
            in: navigableTargets,
            delta: delta
        )
    }

    func moveSelectionHorizontal(delta: Int) {
        selectedTargetID = WindowHubMasonryNavigation.moveSelectionHorizontal(
            selectedTargetID: selectedTargetID,
            columnTargets: masonryColumnTargets,
            delta: delta
        )
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

    func reloadSettings() {
        settings = WindowHubSettingsStore.load()
    }

    func saveSettings(_ newSettings: WindowHubSettings) {
        settings = newSettings
        WindowHubSettingsStore.save(newSettings)
    }

    func replaceSnapshot(_ snapshot: WindowHubSnapshot) {
        self.snapshot = snapshot
    }
}

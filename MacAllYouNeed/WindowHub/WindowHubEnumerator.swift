import ApplicationServices
import AppKit
import Core
import Foundation

enum WindowHubEnumerator {
    private static let log = Logging.logger(for: "window-hub", category: "enumerator")
    private static let providerTimeoutNanoseconds: UInt64 = 250_000_000
    private static let browserAXProvider = BrowserAXTabProvider()

    final class BuildContext: @unchecked Sendable {
        let cgList: [[CFString: Any]]
        let pidsWithWindows: Set<pid_t>
        private let lock = NSLock()
        private var windowsCache: [pid_t: [Bool: [WindowProbe]]] = [:]

        init(cgList: [[CFString: Any]]) {
            self.cgList = cgList
            self.pidsWithWindows = Set(
                cgList.compactMap { info -> pid_t? in
                    guard (info[kCGWindowLayer] as? Int) == 0,
                          let pid = info[kCGWindowOwnerPID] as? pid_t
                    else { return nil }
                    if let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                       let w = bounds["Width"], let h = bounds["Height"], w < 80 || h < 80
                    {
                        return nil
                    }
                    return pid
                }
            )
        }

        func hasVisibleWindow(pid: pid_t) -> Bool {
            pidsWithWindows.contains(pid)
        }

        fileprivate func windows(for pid: pid_t, includeOffSpace: Bool) -> [WindowProbe] {
            lock.lock()
            if let cached = windowsCache[pid]?[includeOffSpace] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let collected = collectWindows(pid: pid, cgList: cgList, includeOffSpace: includeOffSpace)
            lock.lock()
            var perPID = windowsCache[pid, default: [:]]
            perPID[includeOffSpace] = collected
            windowsCache[pid] = perPID
            lock.unlock()
            return collected
        }
    }

    /// Shared-context refresh: shell (fast) then full (tabs + off-space), streaming sections.
    static func refresh(
        settings: WindowHubSettings,
        onSection: (@Sendable (WindowHubAppSection, WindowHubIndexingPhase) async -> Void)? = nil
    ) async -> WindowHubSnapshot {
        guard let context = makeContext() else {
            return failedSnapshot("Accessibility permission required")
        }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var currentTargetID: WindowHubTargetID?

        log.debug("Window Hub shell pass starting")
        let shellSignpost = PerformanceSignpost.WindowHub.beginShellPass()
        let shellStart = Date()
        let shell = await buildPass(
            settings: settings,
            context: context,
            phase: .shell,
            includeTabs: false,
            includeOffSpace: false,
            useChromiumJXA: false,
            frontPID: frontPID,
            onSection: onSection
        )
        currentTargetID = shell.currentTargetID
        PerformanceSignpost.WindowHub.endShellPass(shellSignpost)
        log.debug("Window Hub shell pass finished in \(Date().timeIntervalSince(shellStart), privacy: .public)s")

        log.debug("Window Hub full pass starting")
        let fullSignpost = PerformanceSignpost.WindowHub.beginFullPass()
        let fullStart = Date()
        let full = await buildPass(
            settings: settings,
            context: context,
            phase: .complete,
            includeTabs: true,
            includeOffSpace: true,
            useChromiumJXA: false,
            frontPID: frontPID,
            onSection: onSection
        )
        if full.currentTargetID != nil {
            currentTargetID = full.currentTargetID
        }
        PerformanceSignpost.WindowHub.endFullPass(fullSignpost)
        log.debug("Window Hub full pass finished in \(Date().timeIntervalSince(fullStart), privacy: .public)s")

        return WindowHubSnapshot(
            capturedAt: Date(),
            phase: .complete,
            currentTargetID: currentTargetID ?? full.currentTargetID,
            sections: full.sections,
            flatTargets: WindowHubSectionMerger.flatTargets(from: full.sections),
            timedOutProviders: full.timedOutProviders
        )
    }

    /// Background JXA upgrade for Chromium apps — re-enumerates each app with script tab discovery.
    static func upgradeChromiumApps(
        settings: WindowHubSettings,
        pids: [pid_t],
        onSection: @escaping @Sendable (WindowHubAppSection, WindowHubIndexingPhase) async -> Void
    ) async {
        guard let context = makeContext() else { return }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        await withTaskGroup(of: Void.self) { group in
            for pid in pids {
                group.addTask {
                    let signpost = PerformanceSignpost.WindowHub.beginJXAUpgrade(pid: pid)
                    defer { PerformanceSignpost.WindowHub.endJXAUpgrade(signpost) }
                    guard let app = NSRunningApplication(processIdentifier: pid) else { return }
                    let result = await enumerateApp(
                        app,
                        settings: settings,
                        context: context,
                        includeTabs: true,
                        includeOffSpace: true,
                        useChromiumJXA: true,
                        priority: pid == frontPID
                    )
                    guard !result.section.windowGroups.isEmpty else { return }
                    await onSection(result.section, .complete)
                }
            }
        }
    }

    static func makeContext() -> BuildContext? {
        guard AXIsProcessTrusted() else { return nil }
        WindowHubAXReader.resetForRefresh()
        WindowHubAXWindowBridge.resetForRefresh()
        let cgList = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]]) ?? []
        return BuildContext(cgList: cgList)
    }

    /// Legacy entry points kept for tests / callers.
    static func buildShellSnapshot(settings: WindowHubSettings) async -> WindowHubSnapshot {
        guard let context = makeContext() else {
            return failedSnapshot("Accessibility permission required")
        }
        return await buildPass(
            settings: settings,
            context: context,
            phase: .shell,
            includeTabs: false,
            includeOffSpace: false,
            useChromiumJXA: false,
            frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            onSection: nil
        )
    }

    static func buildSnapshot(
        settings: WindowHubSettings,
        phase: WindowHubIndexingPhase = .incremental,
        includeTabs: Bool = true,
        includeOffSpaceWindows: Bool = true
    ) async -> WindowHubSnapshot {
        guard let context = makeContext() else {
            return failedSnapshot("Accessibility permission required")
        }
        return await buildPass(
            settings: settings,
            context: context,
            phase: phase,
            includeTabs: includeTabs,
            includeOffSpace: includeOffSpaceWindows,
            useChromiumJXA: false,
            frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            onSection: nil
        )
    }

    private static func buildPass(
        settings: WindowHubSettings,
        context: BuildContext,
        phase: WindowHubIndexingPhase,
        includeTabs: Bool,
        includeOffSpace: Bool,
        useChromiumJXA: Bool,
        frontPID: pid_t?,
        onSection: (@Sendable (WindowHubAppSection, WindowHubIndexingPhase) async -> Void)?
    ) async -> WindowHubSnapshot {
        let apps = runningApps(settings: settings, context: context)
        var sections: [WindowHubAppSection] = []
        var timedOut: [String] = []

        let sortedApps = apps.sorted { lhs, rhs in
            if let frontPID {
                if lhs.processIdentifier == frontPID { return true }
                if rhs.processIdentifier == frontPID { return false }
            }
            let lhsName = lhs.localizedName ?? ""
            let rhsName = rhs.localizedName ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        await withTaskGroup(of: (WindowHubAppSection, [WindowHubTarget], Bool, String)?.self) { group in
            for app in sortedApps {
                group.addTask {
                    let result = await enumerateApp(
                        app,
                        settings: settings,
                        context: context,
                        includeTabs: includeTabs,
                        includeOffSpace: includeOffSpace,
                        useChromiumJXA: useChromiumJXA,
                        priority: app.processIdentifier == frontPID
                    )
                    return result
                }
            }
            for await result in group {
                guard let result else { continue }
                if result.2, !timedOut.contains(result.3) { timedOut.append(result.3) }
                if !result.0.windowGroups.isEmpty || settings.showBackgroundApps {
                    sections.append(result.0)
                    if let onSection {
                        let streamPhase: WindowHubIndexingPhase = phase == .shell ? .shell : .incremental
                        await onSection(result.0, streamPhase)
                    }
                }
            }
        }

        sections = WindowHubSectionMerger.sorted(sections, frontPID: frontPID)
        let flatTargets = WindowHubSectionMerger.flatTargets(from: sections)

        let currentTargetID = frontPID.map { pid in
            let windows = context.windows(for: pid, includeOffSpace: includeOffSpace)
            guard let front = windows.first(where: \.isActive) ?? windows.first else {
                return WindowHubTargetID.app(pid: pid)
            }
            return WindowHubTargetID.window(pid: pid, windowID: front.id)
        }

        return WindowHubSnapshot(
            capturedAt: Date(),
            phase: phase,
            currentTargetID: currentTargetID,
            sections: sections,
            flatTargets: flatTargets,
            timedOutProviders: timedOut
        )
    }

    private static func runningApps(settings: WindowHubSettings, context: BuildContext) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            if settings.showBackgroundApps { return true }
            return app.isActive || context.hasVisibleWindow(pid: app.processIdentifier)
        }
    }

    private static func enumerateApp(
        _ app: NSRunningApplication,
        settings: WindowHubSettings,
        context: BuildContext,
        includeTabs: Bool,
        includeOffSpace: Bool,
        useChromiumJXA: Bool,
        priority: Bool
    ) async -> (section: WindowHubAppSection, targets: [WindowHubTarget], timedOut: Bool, providerName: String) {
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier
        let provider = WindowHubTabProviderRegistry.provider(for: bundleID)
        let capabilities = provider.capabilities(for: bundleID)
        let appName = app.localizedName ?? bundleID ?? "App"
        let timeout = priority ? providerTimeoutNanoseconds : providerTimeoutNanoseconds / 2

        let windows = context.windows(for: pid, includeOffSpace: includeOffSpace)
        var providerTimedOut = false

        let chromiumTabsByWindow: [CGWindowID: [WindowHubTabProbe]]
        if includeTabs,
           useChromiumJXA,
           settings.browserTabDiscoveryEnabled,
           let bundleID,
           BrowserAppleScriptTabReader.isChromium(bundleID)
        {
            let probes = windows.map { window in
                BrowserAppleScriptTabCache.WindowProbe(
                    windowID: window.id,
                    title: window.title,
                    usesAppElement: window.usesAppElement,
                    tabCount: BrowserAppleScriptTabCache.axTabCount(pid: pid, windowID: window.id)
                )
            }
            chromiumTabsByWindow = ChromiumBrowserTabProvider.prepareSnapshot(
                pid: pid,
                bundleIdentifier: bundleID,
                probes: probes
            )
        } else {
            chromiumTabsByWindow = [:]
        }

        struct WindowBuildResult: Sendable {
            let windowID: CGWindowID
            let windowTarget: WindowHubTarget
            let tabTargets: [WindowHubTarget]
            let group: WindowHubWindowGroup
        }

        var buildResults: [WindowBuildResult] = []
        await withTaskGroup(of: WindowBuildResult?.self) { group in
            for window in windows {
                group.addTask {
                    let windowID = window.id
                    let title = window.title
                    let windowTarget = WindowHubTarget(
                        id: .window(pid: pid, windowID: windowID),
                        kind: .window,
                        pid: pid,
                        bundleIdentifier: bundleID,
                        appName: appName,
                        windowID: windowID,
                        windowTitle: title,
                        tabTitle: nil,
                        domain: nil,
                        isMinimized: window.isMinimized,
                        isActive: window.isActive,
                        isPinned: false,
                        isAudible: false,
                        isPrivate: false,
                        capabilities: capabilities,
                        riskLevel: .low
                    )

                    let (tabs, windowTimedOut) = await resolveTabs(
                        includeTabs: includeTabs,
                        window: window,
                        pid: pid,
                        bundleID: bundleID,
                        chromiumTabsByWindow: chromiumTabsByWindow,
                        provider: provider,
                        timeoutNanoseconds: timeout
                    )
                    if windowTimedOut, tabs.isEmpty, !window.usesAppElement {
                        providerTimedOut = true
                    }

                    if includeTabs,
                       settings.browserTabDiscoveryEnabled,
                       let bundleID,
                       BrowserAppleScriptTabReader.isChromium(bundleID),
                       !tabs.isEmpty
                    {
                        BrowserAppleScriptTabCache.rememberAXTabCount(
                            pid: pid,
                            windowID: windowID,
                            count: tabs.count
                        )
                    }

                    let isHeavy = tabs.count > WindowHubHeavyWindowPolicy.tabThreshold
                    let tabTargets = tabs.map { tab in
                        WindowHubTarget(
                            id: .tab(pid: pid, windowID: windowID, tabKey: tab.key),
                            kind: .tab,
                            pid: pid,
                            bundleIdentifier: bundleID,
                            appName: appName,
                            windowID: windowID,
                            windowTitle: title,
                            tabTitle: tab.title,
                            domain: tab.domain,
                            isMinimized: window.isMinimized,
                            isActive: tab.isActive,
                            isPinned: tab.isPinned,
                            isAudible: tab.isAudible,
                            isPrivate: tab.isPrivate,
                            capabilities: capabilities,
                            riskLevel: tab.isPrivate || tab.isPinned ? .high : .medium
                        )
                    }

                    let groupTitle = chromiumTabsByWindow[windowID]?.first(where: \.isActive)?.title ?? title
                    let (visibleTargets, hiddenTabCount) = Self.visibleTabPresentation(
                        windowTarget: windowTarget,
                        tabTargets: tabTargets,
                        isHeavy: isHeavy
                    )
                    let windowGroup = WindowHubWindowGroup(
                        id: "\(pid)-\(windowID)",
                        windowID: windowID,
                        title: groupTitle,
                        isMinimized: window.isMinimized,
                        isActive: window.isActive,
                        isHeavy: isHeavy,
                        visibleTargets: visibleTargets,
                        hiddenTabCount: hiddenTabCount,
                        capabilities: capabilities
                    )
                    return WindowBuildResult(
                        windowID: windowID,
                        windowTarget: windowTarget,
                        tabTargets: tabTargets,
                        group: windowGroup
                    )
                }
            }

            for await result in group {
                guard let result else { continue }
                buildResults.append(result)
            }
        }

        buildResults.sort { $0.windowID < $1.windowID }
        let windowGroups = buildResults.map(\.group)

        let section = WindowHubAppSection(
            id: "\(pid)",
            pid: pid,
            bundleIdentifier: bundleID,
            appName: appName,
            windowGroups: windowGroups,
            isBackgroundOnly: windowGroups.isEmpty
        )
        let targets = WindowHubSectionMerger.flatTargets(from: [section])
        return (section, targets, providerTimedOut, provider.providerName)
    }

    private static func visibleTabPresentation(
        windowTarget: WindowHubTarget,
        tabTargets: [WindowHubTarget],
        isHeavy: Bool
    ) -> (visibleTargets: [WindowHubTarget], hiddenTabCount: Int) {
        guard !tabTargets.isEmpty else {
            return ([windowTarget], 0)
        }
        guard isHeavy else {
            return (tabTargets, 0)
        }

        var visible: [WindowHubTarget] = []
        if let active = tabTargets.first(where: \.isActive) {
            visible.append(active)
        }
        let cap = WindowHubHeavyWindowPolicy.visibleTabCap
        let inactive = tabTargets.filter { !$0.isActive }
        let remaining = max(0, cap - visible.count)
        visible.append(contentsOf: inactive.prefix(remaining))
        let hiddenTabCount = max(0, tabTargets.count - visible.count)
        return (visible, hiddenTabCount)
    }

    private static func resolveTabs(
        includeTabs: Bool,
        window: WindowProbe,
        pid: pid_t,
        bundleID: String?,
        chromiumTabsByWindow: [CGWindowID: [WindowHubTabProbe]],
        provider: any WindowHubTabProvider,
        timeoutNanoseconds: UInt64
    ) async -> (tabs: [WindowHubTabProbe], timedOut: Bool) {
        guard includeTabs else { return ([], false) }

        if let chromiumTabs = chromiumTabsByWindow[window.id], !chromiumTabs.isEmpty {
            return (chromiumTabs, false)
        }

        guard !window.usesAppElement else { return ([], false) }

        let axTimeout = browserAXProvider.matches(bundleIdentifier: bundleID)
            ? max(timeoutNanoseconds, 2_000_000_000)
            : timeoutNanoseconds

        return await withTaskGroup(of: (tabs: [WindowHubTabProbe], timedOut: Bool).self) { group in
            group.addTask {
                let tabs: [WindowHubTabProbe]
                if browserAXProvider.matches(bundleIdentifier: bundleID) {
                    tabs = await browserAXProvider.tabs(
                        pid: pid,
                        windowID: window.id,
                        windowElement: window.element,
                        timeoutNanoseconds: axTimeout
                    )
                } else {
                    tabs = await provider.tabs(
                        pid: pid,
                        windowID: window.id,
                        windowElement: window.element,
                        timeoutNanoseconds: timeoutNanoseconds
                    )
                }
                return (tabs, false)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: axTimeout)
                return (tabs: [], timedOut: true)
            }
            let first = await group.next() ?? (tabs: [], timedOut: true)
            group.cancelAll()
            return first
        }
    }

    private static func failedSnapshot(_ message: String) -> WindowHubSnapshot {
        WindowHubSnapshot(
            capturedAt: Date(),
            phase: .failed(message),
            currentTargetID: nil,
            sections: [],
            flatTargets: [],
            timedOutProviders: []
        )
    }

    fileprivate struct WindowProbe {
        let id: CGWindowID
        let title: String
        let element: AXUIElement
        let isMinimized: Bool
        let isActive: Bool
        let usesAppElement: Bool
    }

    private static func collectWindows(
        pid: pid_t,
        cgList: [[CFString: Any]],
        includeOffSpace: Bool
    ) -> [WindowProbe] {
        let appElement = WindowHubAXReader.applicationElement(for: pid)

        var windowsRef: CFTypeRef?
        let axWindows = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success
            ? (windowsRef as? [AXUIElement]) ?? []
            : []

        var results: [WindowProbe] = []
        var matchedWindowIDs = Set<CGWindowID>()

        for (index, axWindow) in axWindows.enumerated() {
            let attrs = WindowHubAXReader.readWindowAttributes(axWindow)
            let axTitle = attrs.title?.trimmingCharacters(in: .whitespacesAndNewlines)

            let windowID = WindowHubAXWindowBridge.windowID(for: axWindow)
                ?? cgWindowID(
                    for: axWindow,
                    pid: pid,
                    cgList: cgList,
                    fallbackIndex: index,
                    position: attrs.position,
                    size: attrs.size
                )
            matchedWindowIDs.insert(windowID)
            let info = cgList.first { ($0[kCGWindowNumber] as? CGWindowID) == windowID }
            let cgTitle = (info?[kCGWindowName] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = [axTitle, cgTitle].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Window"
            let isActive = cgList.first(where: { ($0[kCGWindowNumber] as? CGWindowID) == windowID })?[kCGWindowLayer] as? Int == 0
            results.append(
                WindowProbe(
                    id: windowID,
                    title: title,
                    element: axWindow,
                    isMinimized: attrs.minimized,
                    isActive: isActive,
                    usesAppElement: false
                )
            )
        }

        guard includeOffSpace else { return results }

        let offSpaceTargets = Set(
            cgList.compactMap { info -> CGWindowID? in
                guard (info[kCGWindowOwnerPID] as? pid_t) == pid,
                      (info[kCGWindowLayer] as? Int) == 0,
                      let windowID = info[kCGWindowNumber] as? CGWindowID,
                      !matchedWindowIDs.contains(windowID)
                else { return nil }
                if let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                   let w = bounds["Width"], let h = bounds["Height"], w < 80 || h < 80
                {
                    return nil
                }
                return windowID
            }
        )

        guard !offSpaceTargets.isEmpty else { return results }
        let resolved = WindowHubAXWindowBridge.resolveWindows(pid: pid, targetWindowIDs: offSpaceTargets)

        for windowID in offSpaceTargets.sorted() {
            matchedWindowIDs.insert(windowID)
            let info = cgList.first { ($0[kCGWindowNumber] as? CGWindowID) == windowID }
            let cgTitle = (info?[kCGWindowName] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let element = resolved[windowID] {
                let attrs = WindowHubAXReader.readWindowAttributes(element)
                let axTitle = attrs.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = [axTitle, cgTitle].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Window"
                results.append(
                    WindowProbe(
                        id: windowID,
                        title: title,
                        element: element,
                        isMinimized: attrs.minimized,
                        isActive: false,
                        usesAppElement: false
                    )
                )
            } else {
                let title = cgTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Window"
                results.append(
                    WindowProbe(
                        id: windowID,
                        title: title,
                        element: appElement,
                        isMinimized: false,
                        isActive: false,
                        usesAppElement: true
                    )
                )
            }
        }
        return results
    }

    private static func cgWindowID(
        for axWindow: AXUIElement,
        pid: pid_t,
        cgList: [[CFString: Any]],
        fallbackIndex: Int,
        position: CGPoint?,
        size: CGSize?
    ) -> CGWindowID {
        if let position, let size {
            for info in cgList {
                guard (info[kCGWindowOwnerPID] as? pid_t) == pid else { continue }
                guard let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                      let x = bounds["X"], let y = bounds["Y"],
                      let w = bounds["Width"], let h = bounds["Height"]
                else { continue }
                if abs(x - position.x) < 2, abs(y - position.y) < 2,
                   abs(w - size.width) < 4, abs(h - size.height) < 4,
                   let id = info[kCGWindowNumber] as? CGWindowID
                {
                    return id
                }
            }
        }
        return CGWindowID(fallbackIndex + 1)
    }
}

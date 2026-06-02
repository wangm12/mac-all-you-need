import ApplicationServices
import AppKit
import Foundation
import ScreenCaptureKit

protocol WindowEnumerating: Sendable {
    func windows(
        for pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?,
        disableMinWindowSizeFilter: Bool
    ) async -> [DockPreviewWindowEntry]
}

extension WindowEnumerating {
    func windows(
        for pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?
    ) async -> [DockPreviewWindowEntry] {
        await windows(
            for: pid,
            settings: settings,
            bundleIdentifier: bundleIdentifier,
            disableMinWindowSizeFilter: false
        )
    }
}

/// DockDoor `WindowUtil.getActiveWindows` + `captureAndCacheWindowInfo` + `captureAndCacheAXWindowInfo`.
final class SystemWindowEnumerator: WindowEnumerating, @unchecked Sendable {
    private let api: any DockPreviewPrivateAPI

    init(api: any DockPreviewPrivateAPI = SystemDockPreviewPrivateAPI()) {
        self.api = api
    }

    func windows(
        for pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?,
        disableMinWindowSizeFilter: Bool = false
    ) async -> [DockPreviewWindowEntry] {
        DockPreviewWindowCandidateDiscriminator.disableMinWindowSizeFilter = disableMinWindowSizeFilter

        let displayApp = NSRunningApplication(processIdentifier: pid)
        let pids = targetPIDs(primary: pid, bundleIdentifier: bundleIdentifier, settings: settings)
        var combined: [DockPreviewWindowEntry] = []
        var seenIDs = Set<CGWindowID>()
        for targetPID in pids {
            let app = NSRunningApplication(processIdentifier: targetPID) ?? displayApp
            let entries = await windowsForSinglePID(targetPID, displayApp: app, settings: settings)
            for entry in entries where seenIDs.insert(entry.id).inserted {
                combined.append(entry)
            }
        }
        combined = DockPreviewWindowFilter.filter(combined, settings: settings)
        combined = DockPreviewWindowFilter.filterBySpace(combined, settings: settings)
        combined = DockPreviewWindowOrderStore.sort(combined, bundleIdentifier: bundleIdentifier, order: settings.sortOrder)
        combined = DockPreviewWindowMatcher.deduplicate(combined)
        if settings.ignoreSingleWindowApps, combined.count <= 1 {
            return []
        }
        return combined
    }

    private func targetPIDs(primary: pid_t, bundleIdentifier: String?, settings: DockPreviewSettings) -> [pid_t] {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return [primary] }
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if matches.isEmpty { return [primary] }
        if settings.groupAppInstances || matches.count > 1 {
            return matches.map(\.processIdentifier)
        }
        return [primary]
    }

    private func windowsForSinglePID(
        _ pid: pid_t,
        displayApp: NSRunningApplication?,
        settings: DockPreviewSettings
    ) async -> [DockPreviewWindowEntry] {
        guard let displayApp else { return [] }

        let cgCandidates = DockPreviewCGWindowValidation.candidates(for: displayApp)
        let activeSpaceIDs = DockPreviewSpaceQuery.activeSpaceIDs()

        var entries: [DockPreviewWindowEntry] = []
        var sckWindowIDs = Set<CGWindowID>()

        // Phase 1 — ScreenCaptureKit (DockDoor `captureAndCacheWindowInfo`)
        let scEntries = await discoverScreenCaptureWindows(
            displayApp: displayApp,
            cgCandidates: cgCandidates,
            activeSpaceIDs: activeSpaceIDs,
            settings: settings
        )
        for entry in scEntries {
            sckWindowIDs.insert(entry.id)
            entries.append(entry)
        }

        // Phase 2 — AX fallback excluding SCK ids (DockDoor `discoverWindowsViaAX`)
        let axElements = collectAXWindows(
            displayApp: displayApp,
            cgCandidates: cgCandidates
        )

        for axElement in axElements {
            guard let entry = validatedAXEntry(
                axElement: axElement,
                displayApp: displayApp,
                cgCandidates: cgCandidates,
                activeSpaceIDs: activeSpaceIDs,
                excludeWindowIDs: sckWindowIDs
            ) else { continue }
            guard !sckWindowIDs.contains(entry.id) else { continue }
            entries.append(entry)
        }

        return entries
    }

    private func discoverScreenCaptureWindows(
        displayApp: NSRunningApplication,
        cgCandidates: [[String: AnyObject]],
        activeSpaceIDs: Set<Int>,
        settings: DockPreviewSettings
    ) async -> [DockPreviewWindowEntry] {
        let onScreenOnly = !settings.useBroadWindowDiscovery
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: onScreenOnly) else {
            return []
        }

        var entries: [DockPreviewWindowEntry] = []
        var seenIDs = Set<CGWindowID>()
        let axPool = collectAXWindows(displayApp: displayApp, cgCandidates: cgCandidates)
        var consumedAX = Set<ObjectIdentifier>()

        for window in content.windows {
            guard DockPreviewWindowOwnerResolver.windowBelongsToDisplayApp(window, displayApp: displayApp) else {
                continue
            }
            guard window.windowLayer == 0 else { continue }
            if onScreenOnly {
                guard window.isOnScreen else { continue }
            }
            guard window.frame.width >= DockPreviewCGWindowValidation.minWindowSize.width,
                  window.frame.height >= DockPreviewCGWindowValidation.minWindowSize.height
            else { continue }

            let windowID = CGWindowID(window.windowID)
            guard seenIDs.insert(windowID).inserted else { continue }

            guard let axRef = DockPreviewCGWindowValidation.findMatchingAXWindow(
                windowID: windowID,
                title: window.title,
                frame: window.frame,
                in: axPool.filter { !consumedAX.contains(ObjectIdentifier($0 as AnyObject)) },
                api: api
            ) else { continue }
            consumedAX.insert(ObjectIdentifier(axRef as AnyObject))

            let attributes = DockPreviewWindowCandidateAttributes(axWindow: axRef)
            let hasTrafficLights = hasTrafficLightControls(axRef)
            let level = DockPreviewCGWindowValidation.level(for: windowID, in: cgCandidates)
            guard hasTrafficLights || DockPreviewWindowCandidateDiscriminator.isActualWindow(
                app: displayApp,
                windowID: windowID,
                level: level,
                attributes: attributesAugmented(attributes, cgEntry: DockPreviewCGWindowValidation.entry(for: windowID, in: cgCandidates), frame: window.frame)
            ) else { continue }

            let cgEntry = DockPreviewCGWindowValidation.entry(for: windowID, in: cgCandidates)
                ?? DockPreviewCGWindowValidation.syntheticEntry(
                    for: windowID,
                    frame: window.frame,
                    isOnScreen: window.isOnScreen
                )
            if DockPreviewCGWindowValidation.entry(for: windowID, in: cgCandidates) != nil {
                guard DockPreviewCGWindowValidation.isValidCandidate(windowID, in: cgCandidates) else { continue }
            }

            guard DockPreviewCGWindowValidation.shouldAcceptWindow(
                axWindow: axRef,
                windowID: windowID,
                cgEntry: cgEntry,
                app: displayApp,
                activeSpaceIDs: activeSpaceIDs,
                scBacked: true
            ) else { continue }

            let isMinimized = DockPreviewAXAttributes.bool(axRef, kAXMinimizedAttribute as String) ?? false
            let axTitle = attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let scTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title: String = if !axTitle.isEmpty, axTitle != "Window" {
                axTitle
            } else if !scTitle.isEmpty {
                scTitle
            } else {
                axTitle.isEmpty ? "Window" : axTitle
            }

            entries.append(DockPreviewWindowEntry(
                id: windowID,
                pid: displayApp.processIdentifier,
                title: title,
                frame: window.frame,
                thumbnail: nil,
                isMinimized: isMinimized,
                isOnScreen: window.isOnScreen && !isMinimized
            ))
        }

        return entries
    }

    private func validatedAXEntry(
        axElement: AXUIElement,
        displayApp: NSRunningApplication,
        cgCandidates: [[String: AnyObject]],
        activeSpaceIDs: Set<Int>,
        excludeWindowIDs: Set<CGWindowID>
    ) -> DockPreviewWindowEntry? {
        let attributes = DockPreviewWindowCandidateAttributes(axWindow: axElement)
        var cgID = api.axWindowID(for: axElement) ?? 0

        if cgID == 0 {
            cgID = DockPreviewCGWindowValidation.mapAXToCG(
                attributes: attributes,
                candidates: cgCandidates,
                excluding: excludeWindowIDs
            ) ?? 0
        }
        guard cgID != 0 else { return nil }
        guard !excludeWindowIDs.contains(cgID) else { return nil }

        let cgEntry = DockPreviewCGWindowValidation.entry(for: cgID, in: cgCandidates)
        let bounds = cgEntry?[kCGWindowBounds as String] as? [String: AnyObject]
        let frame = CGRect(
            x: CGFloat((bounds?["X"] as? NSNumber)?.doubleValue ?? 0),
            y: CGFloat((bounds?["Y"] as? NSNumber)?.doubleValue ?? 0),
            width: CGFloat((bounds?["Width"] as? NSNumber)?.doubleValue ?? 0),
            height: CGFloat((bounds?["Height"] as? NSNumber)?.doubleValue ?? 0)
        )
        let augmented = attributesAugmented(attributes, cgEntry: cgEntry, frame: frame)

        let hasTrafficLights = hasTrafficLightControls(axElement)
        let level = DockPreviewCGWindowValidation.level(for: cgID, in: cgCandidates)
        guard hasTrafficLights || DockPreviewWindowCandidateDiscriminator.isActualWindow(
            app: displayApp,
            windowID: cgID,
            level: level,
            attributes: augmented
        ) else { return nil }

        guard let resolvedCGEntry = cgEntry ?? syntheticCGEntryIfValid(
            windowID: cgID,
            frame: frame,
            attributes: augmented
        ) else { return nil }
        if cgEntry != nil {
            guard DockPreviewCGWindowValidation.isValidCandidate(cgID, in: cgCandidates) else { return nil }
        }

        guard DockPreviewCGWindowValidation.shouldAcceptWindow(
            axWindow: axElement,
            windowID: cgID,
            cgEntry: resolvedCGEntry,
            app: displayApp,
            activeSpaceIDs: activeSpaceIDs,
            scBacked: false
        ) else { return nil }

        let isMinimized = DockPreviewAXAttributes.bool(axElement, kAXMinimizedAttribute as String) ?? false
        let axIsFullscreen = DockPreviewAXAttributes.bool(axElement, "AXFullScreen") ?? false
        let cgTitle = (resolvedCGEntry[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let axTitle = attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = !axTitle.isEmpty && axTitle != "Window" ? axTitle : (cgTitle.isEmpty ? axTitle : cgTitle)
        let resolvedFrame: CGRect = if frame != .zero {
            frame
        } else if let pos = augmented.position, let size = augmented.size {
            CGRect(origin: pos, size: size)
        } else {
            .zero
        }
        let hasVisibleFrame = resolvedFrame.width >= DockPreviewCGWindowValidation.minWindowSize.width
            && resolvedFrame.height >= DockPreviewCGWindowValidation.minWindowSize.height

        return DockPreviewWindowEntry(
            id: cgID,
            pid: displayApp.processIdentifier,
            title: title.isEmpty ? "Window" : title,
            frame: resolvedFrame,
            thumbnail: nil,
            isMinimized: isMinimized,
            isOnScreen: axIsFullscreen || (!isMinimized && hasVisibleFrame)
        )
    }

    private func hasTrafficLightControls(_ axWindow: AXUIElement) -> Bool {
        DockPreviewAXAttributes.element(axWindow, kAXCloseButtonAttribute as String) != nil
            || DockPreviewAXAttributes.element(axWindow, kAXMinimizeButtonAttribute as String) != nil
    }

    private func collectAXWindows(
        displayApp: NSRunningApplication,
        cgCandidates: [[String: AnyObject]]
    ) -> [AXUIElement] {
        var axElements: [AXUIElement] = []
        var axSeen = Set<ObjectIdentifier>()
        for ownerPID in ownerPIDs(for: displayApp) {
            let ownerElement = AXUIElementCreateApplication(ownerPID)
            for element in DockPreviewAXWindowDiscovery.allWindows(
                pid: ownerPID,
                appElement: ownerElement,
                app: displayApp,
                api: api,
                cgCandidates: cgCandidates
            ) {
                let token = ObjectIdentifier(element as AnyObject)
                if axSeen.insert(token).inserted {
                    axElements.append(element)
                }
            }
        }
        return axElements
    }

    private func attributesAugmented(
        _ attributes: DockPreviewWindowCandidateAttributes,
        cgEntry: [String: AnyObject]?,
        frame: CGRect
    ) -> DockPreviewWindowCandidateAttributes {
        let cgBounds = cgEntry?[kCGWindowBounds as String] as? [String: AnyObject]
        let cgSize = CGSize(
            width: CGFloat((cgBounds?["Width"] as? NSNumber)?.doubleValue ?? frame.width),
            height: CGFloat((cgBounds?["Height"] as? NSNumber)?.doubleValue ?? frame.height)
        )
        let cgPosition = CGPoint(
            x: CGFloat((cgBounds?["X"] as? NSNumber)?.doubleValue ?? frame.origin.x),
            y: CGFloat((cgBounds?["Y"] as? NSNumber)?.doubleValue ?? frame.origin.y)
        )
        let size = (attributes.size?.width ?? 0) > 0 && (attributes.size?.height ?? 0) > 0
            ? attributes.size
            : (cgSize.width > 0 && cgSize.height > 0 ? cgSize : nil)
        let position = attributes.position ?? (cgPosition.x.isFinite && cgPosition.y.isFinite ? cgPosition : nil)
        return DockPreviewWindowCandidateAttributes(
            title: attributes.title,
            role: attributes.role,
            subrole: attributes.subrole,
            size: size,
            position: position
        )
    }

    private func syntheticCGEntryIfValid(
        windowID: CGWindowID,
        frame: CGRect,
        attributes: DockPreviewWindowCandidateAttributes
    ) -> [String: AnyObject]? {
        guard DockPreviewWindowCandidateDiscriminator.hasUsableSize(frame.size)
            || DockPreviewWindowCandidateDiscriminator.hasUsableSize(attributes.size)
        else { return nil }
        let resolved = frame.size.width > 0 ? frame : CGRect(origin: frame.origin, size: attributes.size ?? frame.size)
        return DockPreviewCGWindowValidation.syntheticEntry(for: windowID, frame: resolved, isOnScreen: true)
    }

    private func ownerPIDs(for displayApp: NSRunningApplication) -> [pid_t] {
        var pids = Set<pid_t>()
        pids.insert(displayApp.processIdentifier)
        for app in NSWorkspace.shared.runningApplications {
            guard DockPreviewWindowOwnerResolver.ownerBelongsToDisplayApp(app, displayApp: displayApp) else { continue }
            pids.insert(app.processIdentifier)
        }
        return Array(pids)
    }
}

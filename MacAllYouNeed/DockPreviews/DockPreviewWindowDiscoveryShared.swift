import AppKit
import ApplicationServices
import Foundation

enum DockPreviewWindowCandidateDiscriminator {
    static var disableMinWindowSizeFilter = false

    private static let minimumSize = CGSize(width: 100, height: 50)
    private static let normalLevel = CGWindowLevelForKey(.normalWindow)
    private static let floatingLevel = CGWindowLevelForKey(.floatingWindow)
    private static let unknownSubrole = "AXUnknown"
    private static let documentWindowSubrole = "AXDocumentWindow"

    static func hasUsableSize(_ size: CGSize?) -> Bool {
        guard let size, size.width > 0, size.height > 0 else { return false }
        if DockPreviewWindowCandidateDiscriminator.disableMinWindowSizeFilter { return true }
        return size.width >= minimumSize.width && size.height >= minimumSize.height
    }

    static func hasUsableGeometry(_ attributes: DockPreviewWindowCandidateAttributes) -> Bool {
        guard hasUsableSize(attributes.size) else { return false }
        if let position = attributes.position {
            return position.x.isFinite && position.y.isFinite
        }
        return true
    }

    static func isActualWindow(app: NSRunningApplication,
                               windowID: CGWindowID,
                               level: Int32,
                               attributes: DockPreviewWindowCandidateAttributes) -> Bool
    {
        rejectionReason(app: app, windowID: windowID, level: level, attributes: attributes) == nil
    }

    static func rejectionReason(app: NSRunningApplication,
                                windowID: CGWindowID,
                                level: Int32,
                                attributes: DockPreviewWindowCandidateAttributes) -> String?
    {
        guard windowID != 0 else { return "missing CGWindowID" }
        return potentialRejectionReason(app: app, level: level, attributes: attributes)
    }

    static func isPotentialAXWindow(app: NSRunningApplication,
                                    level: Int32?,
                                    attributes: DockPreviewWindowCandidateAttributes) -> Bool
    {
        potentialRejectionReason(app: app, level: level, attributes: attributes) == nil
    }

    private static func potentialRejectionReason(app: NSRunningApplication,
                                                 level: Int32?,
                                                 attributes: DockPreviewWindowCandidateAttributes) -> String?
    {
        guard hasUsableGeometry(attributes) else { return "unusable geometry" }

        let specialApp = books(app) ||
            keynote(app) ||
            preview(app, attributes.subrole) ||
            iina(app) ||
            openFLStudio(app, attributes.title) ||
            (level.map { crossoverWindow(app, attributes.role, attributes.subrole, $0) } ?? false) ||
            (level.map { alwaysOnTopScrcpy(app, $0, attributes.role, attributes.subrole) } ?? false)

        let standardSubrole = [kAXStandardWindowSubrole as String, kAXDialogSubrole as String].contains(attributes.subrole ?? "")
        let appSpecificSubrole = openBoard(app) ||
            adobeAudition(app, attributes.subrole) ||
            adobeAfterEffects(app, attributes.subrole) ||
            steam(app, attributes.title, attributes.role) ||
            worldOfWarcraft(app, attributes.role) ||
            battleNetBootstrapper(app, attributes.role) ||
            firefox(app, attributes.role, attributes.size) ||
            vlcFullscreenVideo(app, attributes.role) ||
            sanGuoShaAirWD(app) ||
            dvdFab(app) ||
            drBetotte(app) ||
            androidEmulator(app, attributes.title, attributes.role, level) ||
            autocad(app, attributes.subrole)

        guard specialApp || standardSubrole || appSpecificSubrole else {
            return "subrole is not standard/dialog and no app-specific rule matched"
        }

        if !specialApp {
            guard mustHaveIfJetBrainsApp(app, attributes.title, attributes.subrole, attributes.size),
                  mustHaveIfSteam(app, attributes.title, attributes.role),
                  mustHaveIfFusion360(app, attributes.title),
                  mustHaveIfColorSlurp(app, attributes.subrole)
            else { return "app-specific hard requirement failed" }
        }

        return nil
    }

    private static func hasNonEmptyTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func mustHaveIfFusion360(_ app: NSRunningApplication, _ title: String?) -> Bool {
        app.bundleIdentifier != "com.autodesk.fusion360" || hasNonEmptyTitle(title)
    }

    private static func mustHaveIfJetBrainsApp(_ app: NSRunningApplication, _ title: String?, _ subrole: String?, _ size: CGSize?) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier.hasPrefix("com.jetbrains.") || bundleIdentifier.hasPrefix("com.google.android.studio")
        else { return true }

        return (subrole == kAXStandardWindowSubrole as String || hasNonEmptyTitle(title)) &&
            (size?.width ?? 0) > 100 &&
            (size?.height ?? 0) > 100
    }

    private static func mustHaveIfColorSlurp(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier != "com.IdeaPunch.ColorSlurp" || subrole == kAXStandardWindowSubrole
    }

    private static func iina(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.colliderli.iina"
    }

    private static func keynote(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.apple.iWork.Keynote"
    }

    private static func preview(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier == "com.apple.Preview" && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole)
    }

    private static func openFLStudio(_ app: NSRunningApplication, _ title: String?) -> Bool {
        app.bundleIdentifier == "com.image-line.flstudio" && hasNonEmptyTitle(title)
    }

    private static func openBoard(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "org.oe-f.OpenBoard"
    }

    private static func adobeAudition(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier == "com.adobe.Audition" && subrole == kAXFloatingWindowSubrole
    }

    private static func adobeAfterEffects(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        app.bundleIdentifier == "com.adobe.AfterEffects" && subrole == kAXFloatingWindowSubrole
    }

    private static func books(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.apple.iBooksX"
    }

    private static func worldOfWarcraft(_ app: NSRunningApplication, _ role: String?) -> Bool {
        app.bundleIdentifier == "com.blizzard.worldofwarcraft" && role == kAXWindowRole
    }

    private static func battleNetBootstrapper(_ app: NSRunningApplication, _ role: String?) -> Bool {
        app.bundleIdentifier == "net.battle.bootstrapper" && role == kAXWindowRole
    }

    private static func drBetotte(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.ssworks.drbetotte"
    }

    private static func dvdFab(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "com.goland.dvdfab.macos"
    }

    private static func sanGuoShaAirWD(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == "SanGuoShaAirWD"
    }

    private static func steam(_ app: NSRunningApplication, _ title: String?, _ role: String?) -> Bool {
        app.bundleIdentifier == "com.valvesoftware.steam" && hasNonEmptyTitle(title) && role != nil
    }

    private static func mustHaveIfSteam(_ app: NSRunningApplication, _ title: String?, _ role: String?) -> Bool {
        app.bundleIdentifier != "com.valvesoftware.steam" || (hasNonEmptyTitle(title) && role != nil)
    }

    private static func firefox(_ app: NSRunningApplication, _ role: String?, _ size: CGSize?) -> Bool {
        (app.bundleIdentifier?.hasPrefix("org.mozilla.firefox") ?? false) &&
            role == kAXWindowRole &&
            (size?.height ?? 0) > 400
    }

    private static func vlcFullscreenVideo(_ app: NSRunningApplication, _ role: String?) -> Bool {
        (app.bundleIdentifier?.hasPrefix("org.videolan.vlc") ?? false) && role == kAXWindowRole
    }

    private static func androidEmulator(_ app: NSRunningApplication, _ title: String?, _ role: String?, _ level: Int32?) -> Bool {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard app.bundleIdentifier == nil,
              role == kAXWindowRole,
              let title,
              !title.isEmpty,
              title != "Window",
              level == nil || level == normalLevel
        else { return false }
        return app.executableURL?.lastPathComponent.range(of: "qemu-system[^/]*$", options: .regularExpression) != nil
    }

    private static func crossoverWindow(_ app: NSRunningApplication, _ role: String?, _ subrole: String?, _ level: Int32) -> Bool {
        app.bundleIdentifier == nil &&
            role == kAXWindowRole &&
            subrole == unknownSubrole &&
            level == normalLevel &&
            (app.executableURL?.lastPathComponent == "wine64-preloader" || (app.executableURL?.absoluteString.contains("/winetemp-") ?? false))
    }

    private static func alwaysOnTopScrcpy(_ app: NSRunningApplication, _ level: Int32, _ role: String?, _ subrole: String?) -> Bool {
        app.executableURL?.lastPathComponent == "scrcpy" &&
            level == floatingLevel &&
            role == kAXWindowRole &&
            subrole == kAXStandardWindowSubrole
    }

    private static func autocad(_ app: NSRunningApplication, _ subrole: String?) -> Bool {
        (app.bundleIdentifier?.hasPrefix("com.autodesk.AutoCAD") ?? false) && subrole == documentWindowSubrole
    }
}

enum DockPreviewCGWindowValidation {
    static let minWindowSize = CGSize(width: 100, height: 100)

    static func mapAXToCG(
        attributes: DockPreviewWindowCandidateAttributes,
        candidates: [[String: AnyObject]],
        excluding: Set<CGWindowID>
    ) -> CGWindowID? {
        let axTitle = attributes.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let axPos = attributes.position
        let axSize = attributes.size

        if !axTitle.isEmpty {
            if let match = candidates.first(where: { desc in
                let title = (desc[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
                return title == axTitle && !excluding.contains(wid)
            }) {
                return CGWindowID((match[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            }
        }

        if let p = axPos, let s = axSize, s != .zero {
            let tol: CGFloat = 2.0
            if let match = candidates.first(where: { desc in
                let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
                if excluding.contains(wid) { return false }
                let bounds = desc[kCGWindowBounds as String] as? [String: AnyObject]
                let rx = CGFloat((bounds?["X"] as? NSNumber)?.doubleValue ?? .infinity)
                let ry = CGFloat((bounds?["Y"] as? NSNumber)?.doubleValue ?? .infinity)
                let rw = CGFloat((bounds?["Width"] as? NSNumber)?.doubleValue ?? .infinity)
                let rh = CGFloat((bounds?["Height"] as? NSNumber)?.doubleValue ?? .infinity)
                let r = CGRect(x: rx, y: ry, width: rw, height: rh)
                let posMatch = abs(r.origin.x - p.x) <= tol && abs(r.origin.y - p.y) <= tol
                let sizeMatch = abs(r.size.width - s.width) <= tol && abs(r.size.height - s.height) <= tol
                return posMatch && sizeMatch
            }) {
                return CGWindowID((match[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            }
        }

        if !axTitle.isEmpty {
            if let match = candidates.first(where: { desc in
                let title = ((desc[kCGWindowName as String] as? String) ?? "").lowercased()
                let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
                return !excluding.contains(wid) && title.contains(axTitle.lowercased())
            }) {
                return CGWindowID((match[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            }
        }

        return nil
    }

    static func candidates(for displayApp: NSRunningApplication) -> [[String: AnyObject]] {
        let cgAll = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]]) ?? []
        return cgAll.filter { desc in
            let ownerPID = (desc[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            guard let owner = NSRunningApplication(processIdentifier: ownerPID) else { return false }
            return DockPreviewWindowOwnerResolver.ownerBelongsToDisplayApp(owner, displayApp: displayApp)
        }.sorted { first, second in
            let firstLayer = (first[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let secondLayer = (second[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            return firstLayer == 0 && secondLayer != 0
        }
    }

    static func candidates(for pid: pid_t) -> [[String: AnyObject]] {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
        return candidates(for: app)
    }

    static func entry(for windowID: CGWindowID, in candidates: [[String: AnyObject]]) -> [String: AnyObject]? {
        candidates.first { desc in
            CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0) == windowID
        }
    }

    static func level(for windowID: CGWindowID, in candidates: [[String: AnyObject]]) -> Int32 {
        Int32((entry(for: windowID, in: candidates)?[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
    }

    static func isValidCandidate(_ id: CGWindowID, in candidates: [[String: AnyObject]]) -> Bool {
        guard let match = entry(for: id, in: candidates) else { return false }
        let bounds = match[kCGWindowBounds as String] as? [String: AnyObject]
        let rw = CGFloat((bounds?["Width"] as? NSNumber)?.doubleValue ?? 0)
        let rh = CGFloat((bounds?["Height"] as? NSNumber)?.doubleValue ?? 0)
        let alpha = CGFloat((match[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0)
        if !DockPreviewWindowCandidateDiscriminator.hasUsableSize(CGSize(width: rw, height: rh)) { return false }
        if alpha <= 0.01 { return false }
        return true
    }

    static func shouldAcceptWindow(
        axWindow: AXUIElement,
        windowID: CGWindowID,
        cgEntry: [String: AnyObject],
        app: NSRunningApplication,
        activeSpaceIDs: Set<Int>,
        scBacked: Bool
    ) -> Bool {
        let isOnscreen = (cgEntry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
        let axIsFullscreen = DockPreviewAXAttributes.bool(axWindow, "AXFullScreen") ?? false
        let axIsMinimized = DockPreviewAXAttributes.bool(axWindow, kAXMinimizedAttribute as String) ?? false
        let windowSpaces = Set(DockPreviewSpaceQuery.spaceIDs(for: windowID))

        let isOnActiveSpace = !windowSpaces.isEmpty && !windowSpaces.isDisjoint(with: activeSpaceIDs)
        let isGhostWindow = isOnscreen == false && isOnActiveSpace && !axIsMinimized && !axIsFullscreen && !app.isHidden
        if isGhostWindow { return false }

        if isOnscreen == true || scBacked { return true }
        if app.isHidden || axIsFullscreen || axIsMinimized { return true }

        if !windowSpaces.isEmpty, windowSpaces.isDisjoint(with: activeSpaceIDs) {
            if isOnscreen == false, !axIsMinimized, !axIsFullscreen, !app.isHidden {
                return false
            }
            return true
        }

        if DockPreviewAXAttributes.bool(axWindow, kAXMainAttribute as String) == true {
            return true
        }

        return false
    }

    static func syntheticEntry(for windowID: CGWindowID, frame: CGRect, isOnScreen: Bool) -> [String: AnyObject] {
        [
            kCGWindowNumber as String: NSNumber(value: windowID),
            kCGWindowIsOnscreen as String: NSNumber(value: isOnScreen),
            kCGWindowAlpha as String: NSNumber(value: 1.0),
            kCGWindowBounds as String: [
                "X": NSNumber(value: frame.origin.x),
                "Y": NSNumber(value: frame.origin.y),
                "Width": NSNumber(value: frame.width),
                "Height": NSNumber(value: frame.height),
            ] as AnyObject,
        ]
    }

    static func findMatchingAXWindow(
        windowID: CGWindowID,
        title: String?,
        frame: CGRect,
        in axWindows: [AXUIElement],
        api: any DockPreviewPrivateAPI
    ) -> AXUIElement? {
        if let matched = axWindows.first(where: { api.axWindowID(for: $0) == windowID }) {
            return matched
        }
        if let title, !title.isEmpty {
            for axWindow in axWindows {
                if let axTitle = DockPreviewAXAttributes.string(axWindow, kAXTitleAttribute as String),
                   fuzzyTitleMatch(windowTitle: title, axTitle: axTitle) {
                    return axWindow
                }
            }
        }
        for axWindow in axWindows {
            guard let axPosition = DockPreviewAXAttributes.point(axWindow),
                  let axSize = DockPreviewAXAttributes.size(axWindow),
                  axPosition != .zero, axSize != .zero
            else { continue }
            let positionThreshold: CGFloat = 10
            let sizeThreshold: CGFloat = 10
            let positionMatch = abs(axPosition.x - frame.origin.x) <= positionThreshold
                && abs(axPosition.y - frame.origin.y) <= positionThreshold
            let sizeMatch = abs(axSize.width - frame.size.width) <= sizeThreshold
                && abs(axSize.height - frame.size.height) <= sizeThreshold
            if positionMatch, sizeMatch { return axWindow }
        }
        return nil
    }

    static func fuzzyTitleMatch(windowTitle: String, axTitle: String) -> Bool {
        let axTitleWords = axTitle.lowercased().split(separator: " ")
        let windowTitleWords = windowTitle.lowercased().split(separator: " ")
        let matchingWords = axTitleWords.filter { windowTitleWords.contains($0) }
        let matchPercentage = Double(matchingWords.count) / Double(max(windowTitleWords.count, 1))
        return matchPercentage >= 0.90 || axTitle.lowercased().contains(windowTitle.lowercased())
    }
}

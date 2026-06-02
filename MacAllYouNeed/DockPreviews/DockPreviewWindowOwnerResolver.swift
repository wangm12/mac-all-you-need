import AppKit
import ScreenCaptureKit

/// DockDoor `WindowOwnerResolver` — maps helper/renderer PIDs (Electron, etc.) to the display app.
enum DockPreviewWindowOwnerResolver {
    static func ownerApp(for window: SCWindow) -> NSRunningApplication? {
        guard let pid = window.owningApplication?.processID else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    static func windowBelongsToDisplayApp(_ window: SCWindow, displayApp: NSRunningApplication) -> Bool {
        guard let owner = ownerApp(for: window) else { return false }
        return ownerBelongsToDisplayApp(owner, displayApp: displayApp)
    }

    static func ownerBelongsToDisplayApp(_ owner: NSRunningApplication, displayApp: NSRunningApplication) -> Bool {
        if owner.processIdentifier == displayApp.processIdentifier {
            return true
        }

        guard canResolveThroughDisplayApp(owner) else {
            return false
        }

        if helperBundleBelongsToDisplayApp(owner.bundleIdentifier, displayApp.bundleIdentifier) {
            return true
        }

        return executableRootsMatch(owner: owner, displayApp: displayApp)
    }

    /// DockDoor `displayApp(forOwner:)` — map helper/renderer to the user-facing app.
    static func displayApp(forOwner owner: NSRunningApplication) -> NSRunningApplication {
        guard canResolveThroughDisplayApp(owner) else {
            return owner
        }

        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && ownerBelongsToDisplayApp(owner, displayApp: $0)
        }

        if let parentBundleApp = candidates
            .filter({
                $0.processIdentifier != owner.processIdentifier
                    && bundleIsParent($0.bundleIdentifier, of: owner.bundleIdentifier)
            })
            .sorted(by: { displayAppScore($0, forOwner: owner) > displayAppScore($1, forOwner: owner) })
            .first
        {
            return parentBundleApp
        }

        return candidates.sorted {
            displayAppScore($0, forOwner: owner) > displayAppScore($1, forOwner: owner)
        }.first ?? owner
    }

    private static func bundleIsParent(_ parentBundle: String?, of childBundle: String?) -> Bool {
        guard let parentBundle, let childBundle else { return false }
        return childBundle.hasPrefix(parentBundle + ".")
    }

    private static func displayAppScore(_ displayApp: NSRunningApplication, forOwner owner: NSRunningApplication) -> Int {
        var score = 0
        if owner.processIdentifier == displayApp.processIdentifier { score += 100 }
        if owner.bundleIdentifier == displayApp.bundleIdentifier { score += 80 }
        if let ownerBundle = owner.bundleIdentifier,
           let displayBundle = displayApp.bundleIdentifier,
           ownerBundle.hasPrefix(displayBundle + ".")
        {
            score += 90
            score += max(0, 30 - (displayBundle.count / 4))
        } else if helperBundleBelongsToDisplayApp(owner.bundleIdentifier, displayApp.bundleIdentifier) {
            score += 50
        }
        if executableRootsMatch(owner: owner, displayApp: displayApp) { score += 10 }
        return score
    }

    private static func canResolveThroughDisplayApp(_ owner: NSRunningApplication) -> Bool {
        owner.activationPolicy != .regular || owner.bundleIdentifier == nil
    }

    private static func helperBundleBelongsToDisplayApp(_ ownerBundle: String?, _ displayBundle: String?) -> Bool {
        guard let ownerBundle, let displayBundle else { return false }
        return ownerBundle == displayBundle || ownerBundle.hasPrefix(displayBundle + ".")
    }

    private static func executableRootsMatch(owner: NSRunningApplication, displayApp: NSRunningApplication) -> Bool {
        guard let ownerPath = owner.executableURL?.standardizedFileURL.path,
              let displayPath = displayApp.executableURL?.standardizedFileURL.path
        else { return false }

        let ownerComponents = ownerPath.split(separator: "/")
        let displayComponents = displayPath.split(separator: "/")
        let commonPrefixCount = zip(ownerComponents, displayComponents).prefix { $0 == $1 }.count

        return commonPrefixCount >= 5
    }
}

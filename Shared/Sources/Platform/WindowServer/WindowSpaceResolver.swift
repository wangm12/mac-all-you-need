import AppKit
import Foundation

public typealias ManagedSpaceID = Int

/// Resolves Mission Control managed spaces from CGS private APIs.
public struct WindowSpaceResolver: Sendable {
    private let api: any WindowServerPrivateAPI

    public init(api: any WindowServerPrivateAPI = SystemWindowServerPrivateAPI.shared) {
        self.api = api
    }

    public var separateSpacesEnabled: Bool {
        NSScreen.screensHaveSeparateSpaces
    }

    public func currentManagedSpaceID(mouseLocation: CGPoint = NSEvent.mouseLocation) -> ManagedSpaceID? {
        guard let displays = api.managedDisplaySpaces() else { return nil }
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: AnyObject]] else { continue }
            let current = display["Current Space"] as? [String: AnyObject]
            if let id = spaceID(from: current) {
                let screen = screenForDisplayDictionary(display)
                if screen?.frame.contains(mouseLocation) == true {
                    return id
                }
            }
            for space in spaces where space["ManagedSpaceID"] != nil {
                if let id = spaceID(from: space),
                   let screen = screenForDisplayDictionary(display),
                   screen.frame.contains(mouseLocation)
                {
                    return id
                }
            }
        }
        return orderedSpaceIDs().first
    }

    public func orderedSpaceIDs() -> [ManagedSpaceID] {
        guard let displays = api.managedDisplaySpaces() else { return [] }
        var result: [ManagedSpaceID] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: AnyObject]] else { continue }
            for space in spaces {
                if let id = spaceID(from: space) {
                    result.append(id)
                }
            }
        }
        return result
    }

    public func nextSpace(after current: ManagedSpaceID?) -> ManagedSpaceID? {
        let ordered = orderedSpaceIDs()
        guard !ordered.isEmpty else { return nil }
        guard let current, let index = ordered.firstIndex(of: current) else { return ordered.first }
        let next = index + 1
        return next < ordered.count ? ordered[next] : ordered.first
    }

    public func previousSpace(before current: ManagedSpaceID?) -> ManagedSpaceID? {
        let ordered = orderedSpaceIDs()
        guard !ordered.isEmpty else { return nil }
        guard let current, let index = ordered.firstIndex(of: current) else { return ordered.last }
        let prev = index - 1
        return prev >= 0 ? ordered[prev] : ordered.last
    }

    private func spaceID(from dictionary: [String: AnyObject]?) -> ManagedSpaceID? {
        guard let dict = dictionary else { return nil }
        if let n = dict["id"] as? Int { return n }
        if let n = dict["ManagedSpaceID"] as? Int { return n }
        return nil
    }

    private func screenForDisplayDictionary(_ display: [String: AnyObject]) -> NSScreen? {
        guard let displayID = display["Display Identifier"] as? UInt32 else {
            return NSScreen.main
        }
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == displayID
        } ?? NSScreen.main
    }
}

import AppKit
import ApplicationServices
import Foundation

public enum WindowSpaceMoveResult: Equatable, Sendable {
    case moved
    case unavailable
    case separateSpacesDisabled
    case windowNotFound
}

/// Moves windows between managed Mission Control spaces via CGS/SkyLight.
public struct WindowSpaceMover: Sendable {
    private let api: any WindowServerPrivateAPI
    private let resolver: WindowSpaceResolver

    public init(
        api: any WindowServerPrivateAPI = SystemWindowServerPrivateAPI.shared,
        resolver: WindowSpaceResolver? = nil
    ) {
        self.api = api
        self.resolver = resolver ?? WindowSpaceResolver(api: api)
    }

    public func moveFrontWindowToNextSpace(element: AXUIElement) -> WindowSpaceMoveResult {
        move(element: element, target: resolver.nextSpace(after: currentSpace(for: element)))
    }

    public func moveFrontWindowToPreviousSpace(element: AXUIElement) -> WindowSpaceMoveResult {
        move(element: element, target: resolver.previousSpace(before: currentSpace(for: element)))
    }

    private func move(element: AXUIElement, target: ManagedSpaceID?) -> WindowSpaceMoveResult {
        guard resolver.separateSpacesEnabled else { return .separateSpacesDisabled }
        guard let windowID = api.axWindowID(for: element) else { return .windowNotFound }
        guard let target else { return .unavailable }
        guard api.moveWindowsToManagedSpace([windowID], spaceID: UInt64(target)) else {
            return .unavailable
        }
        return .moved
    }

    private func currentSpace(for element: AXUIElement) -> ManagedSpaceID? {
        guard let windowID = api.axWindowID(for: element),
              let map = api.copySpaces(forWindowIDs: [windowID]),
              let spaces = map[windowID],
              let first = spaces.first
        else { return resolver.currentManagedSpaceID() }
        return first
    }
}

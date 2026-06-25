import AppKit
import Foundation

// MARK: - Identifiers

struct WindowHubTargetID: Hashable, Codable, Sendable {
    let raw: String

    static func window(pid: pid_t, windowID: CGWindowID) -> WindowHubTargetID {
        WindowHubTargetID(raw: "w:\(pid):\(windowID)")
    }

    static func tab(pid: pid_t, windowID: CGWindowID, tabKey: String) -> WindowHubTargetID {
        WindowHubTargetID(raw: "t:\(pid):\(windowID):\(tabKey)")
    }

    static func app(pid: pid_t) -> WindowHubTargetID {
        WindowHubTargetID(raw: "a:\(pid)")
    }
}

// MARK: - Capabilities

struct TabCapability: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    static let list = TabCapability(rawValue: 1 << 0)
    static let focus = TabCapability(rawValue: 1 << 1)
    static let close = TabCapability(rawValue: 1 << 2)
    static let move = TabCapability(rawValue: 1 << 3)
    static let create = TabCapability(rawValue: 1 << 4)
    static let readURL = TabCapability(rawValue: 1 << 5)
    static let readDomain = TabCapability(rawValue: 1 << 6)

    static let windowOnly: TabCapability = [.list, .focus]
    static let browserAX: TabCapability = [.list, .focus, .close, .readDomain]
    static let browserScript: TabCapability = [.list, .focus, .close, .move, .create, .readURL, .readDomain]
}

enum WindowHubTargetKind: String, Codable, Sendable {
    case app
    case window
    case tab
}

enum WindowHubRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

// MARK: - Targets

struct WindowHubTarget: Identifiable, Hashable, Sendable, Codable {
    let id: WindowHubTargetID
    let kind: WindowHubTargetKind
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let windowID: CGWindowID?
    let windowTitle: String?
    let tabTitle: String?
    let domain: String?
    let isMinimized: Bool
    let isActive: Bool
    let isPinned: Bool
    let isAudible: Bool
    let isPrivate: Bool
    let capabilities: TabCapability
    let riskLevel: WindowHubRiskLevel

    var displayTitle: String {
        switch kind {
        case .app: appName
        case .window: windowTitle?.isEmpty == false ? windowTitle! : appName
        case .tab: tabTitle?.isEmpty == false ? tabTitle! : (windowTitle ?? appName)
        }
    }

    var breadcrumb: String {
        switch kind {
        case .app:
            return appName
        case .window:
            return "\(appName) › \(displayTitle)"
        case .tab:
            let window = windowTitle ?? "Window"
            return "\(appName) › \(window) › \(displayTitle)"
        }
    }
}

struct WindowHubWindowGroup: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let windowID: CGWindowID
    let title: String
    let isMinimized: Bool
    let isActive: Bool
    let isHeavy: Bool
    let visibleTargets: [WindowHubTarget]
    let hiddenTabCount: Int
    let capabilities: TabCapability
}

struct WindowHubAppSection: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let windowGroups: [WindowHubWindowGroup]
    let isBackgroundOnly: Bool
}

enum WindowHubIndexingPhase: Equatable, Sendable {
    case idle
    case stale
    case shell
    case currentContext
    case incremental
    case complete
    case failed(String)
}

/// Persisted snapshot payload (phase is assigned at load time).
struct WindowHubCachedSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    let capturedAt: Date
    let currentTargetID: WindowHubTargetID?
    let sections: [WindowHubAppSection]
    let flatTargets: [WindowHubTarget]

    init(
        capturedAt: Date,
        currentTargetID: WindowHubTargetID?,
        sections: [WindowHubAppSection],
        flatTargets: [WindowHubTarget]? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.capturedAt = capturedAt
        self.currentTargetID = currentTargetID
        self.sections = sections
        self.flatTargets = flatTargets ?? WindowHubSectionMerger.flatTargets(from: sections)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        currentTargetID = try container.decodeIfPresent(WindowHubTargetID.self, forKey: .currentTargetID)
        sections = try container.decode([WindowHubAppSection].self, forKey: .sections)
        flatTargets = try container.decode([WindowHubTarget].self, forKey: .flatTargets)
    }

    /// Returns a cache entry with recomputed `flatTargets`, or `nil` when the schema is too new.
    func validated() -> WindowHubCachedSnapshot? {
        guard schemaVersion == 0 || schemaVersion == Self.currentSchemaVersion else { return nil }
        let expectedTargets = WindowHubSectionMerger.flatTargets(from: sections)
        guard flatTargets.map(\.id) != expectedTargets.map(\.id) else { return self }
        return WindowHubCachedSnapshot(
            capturedAt: capturedAt,
            currentTargetID: currentTargetID,
            sections: sections,
            flatTargets: expectedTargets
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case capturedAt
        case currentTargetID
        case sections
        case flatTargets
    }
}

enum WindowHubSectionMerger {
    static func upsert(
        _ section: WindowHubAppSection,
        into sections: inout [WindowHubAppSection]
    ) {
        if let index = sections.firstIndex(where: { $0.pid == section.pid }) {
            sections[index] = section
        } else {
            sections.append(section)
        }
    }

    static func sorted(
        _ sections: [WindowHubAppSection],
        frontPID: pid_t?
    ) -> [WindowHubAppSection] {
        sections.sorted { lhs, rhs in
            if let frontPID {
                if lhs.pid == frontPID { return true }
                if rhs.pid == frontPID { return false }
            }
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }

    static func flatTargets(from sections: [WindowHubAppSection]) -> [WindowHubTarget] {
        sections.flatMap { section in
            section.windowGroups.flatMap(\.visibleTargets)
        }
    }
}

struct WindowHubSnapshot: Sendable {
    let capturedAt: Date
    let phase: WindowHubIndexingPhase
    let currentTargetID: WindowHubTargetID?
    let sections: [WindowHubAppSection]
    let flatTargets: [WindowHubTarget]
    let timedOutProviders: [String]

    static let empty = WindowHubSnapshot(
        capturedAt: .distantPast,
        phase: .idle,
        currentTargetID: nil,
        sections: [],
        flatTargets: [],
        timedOutProviders: []
    )
}

enum WindowHubSwitchResult: Equatable, Sendable {
    case switched
    case switchedAppOnly
    case staleWindow
    case permissionDenied
    case timeout
    case unsupported
}

enum WindowHubPanelMode: Equatable, Sendable {
    case dashboard
    case searchResults
    case browseColumns
    case actionConfirmation
}

enum WindowHubDirectAction: String, Codable, Sendable, CaseIterable {
    case closeTab
    case closeWindow
    case closeAllTabsInWindow
    case quitApp
}

struct WindowHubActionStep: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let action: WindowHubDirectAction?
    let targetID: WindowHubTargetID
    let executable: Bool
    let reason: String?
}

struct WindowHubActionPlan: Sendable {
    let title: String
    let steps: [WindowHubActionStep]
    let requiresConfirmation: Bool
    let canUndo: Bool
}

enum WindowHubActionExecutionState: Equatable, Sendable {
    case idle
    case running(completed: Int, total: Int)
    case cancelled
    case finished(succeeded: Int, failed: Int)
}

struct WindowHubAIPlanStep: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let kind: String
    let targetID: String?
    let title: String
    let executable: Bool
    let reason: String?
}

struct WindowHubAIPlan: Codable, Sendable {
    let summary: String
    let steps: [WindowHubAIPlanStep]
}

enum WindowHubHeavyWindowPolicy {
    /// Windows with more tabs than this collapse to "active + recent" in the dashboard.
    /// Kept small so SwiftUI never lays out hundreds of rows on the main thread.
    static let tabThreshold = 7
    static let visibleTabCap = 6
    static let sectionRowCap = 36
}

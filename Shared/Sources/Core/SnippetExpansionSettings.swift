import Foundation

public enum SnippetExpansionMode: String, CaseIterable, Identifiable, Sendable {
    case autoExpand
    case confirmWithTab
    case disabled

    public var id: String { rawValue }
}

public enum SnippetExpansionSettings {
    public static let modeKey = "snippets.expansion.mode"
    public static let defaultMode = SnippetExpansionMode.autoExpand

    public static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> SnippetExpansionMode {
        SnippetExpansionMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? defaultMode
    }
}

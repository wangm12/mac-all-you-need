import Foundation

/// Centralized accessors for Clipboard Smart Text preferences, persisted in the
/// shared App Group `UserDefaults`. Read by the daemon capture hot path and the
/// main-app enrichment coordinator; written by the settings UI. Defaults keep
/// the feature conservative: sensitive filtering on, link cleaning automatic.
public enum SmartTextSettings {
    public enum LinkMode: String, CaseIterable, Sendable {
        case off, manual, auto
    }

    enum Key {
        static let calculation = "smarttext.calculationEnabled"
        static let linkMode = "smarttext.linkMode"
        static let detection = "smarttext.detectionEnabled"
        static let ocr = "smarttext.ocrEnabled"
        static let sensitive = "smarttext.sensitiveEnabled"
        static let semantic = "smarttext.semanticEnabled"
        static let copyShortcutEnabled = "smarttext.copyShortcutEnabled"
        static let optionDoubleClickEnabled = "smarttext.optionDoubleClickEnabled"
    }

    private static func bool(_ key: String, default def: Bool, _ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? def
    }

    public static func calculationEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.calculation, default: true, defaults)
    }
    public static func detectionEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.detection, default: true, defaults)
    }
    public static func ocrEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.ocr, default: true, defaults)
    }
    public static func sensitiveEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.sensitive, default: true, defaults)
    }
    public static func semanticEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.semantic, default: false, defaults)
    }
    public static func linkMode(_ defaults: UserDefaults = AppGroupSettings.defaults) -> LinkMode {
        guard let raw = defaults.string(forKey: Key.linkMode), let mode = LinkMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }

    public static func setCalculationEnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.calculation)
    }
    public static func setDetectionEnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.detection)
    }
    public static func setOCREnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.ocr)
    }
    public static func setSensitiveEnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.sensitive)
    }
    public static func setSemanticEnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.semantic)
    }
    public static func copyShortcutEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.copyShortcutEnabled, default: true, defaults)
    }
    public static func optionDoubleClickEnabled(_ defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        bool(Key.optionDoubleClickEnabled, default: true, defaults)
    }
    public static func setCopyShortcutEnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.copyShortcutEnabled)
    }
    public static func setOptionDoubleClickEnabled(_ value: Bool, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value, forKey: Key.optionDoubleClickEnabled)
    }
    public static func setLinkMode(_ value: LinkMode, _ defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(value.rawValue, forKey: Key.linkMode)
    }
}

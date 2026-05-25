import Core
import FeatureCore
import Foundation

/// Read-only probe over `AppGroupSettings` + the shared GRDB stores. Returns the strongest
/// usage signal we can find for each feature. Closures injected so tests can drive the matrix
/// without touching real DB files.
struct PriorUsageDetector {
    typealias CountProvider = () throws -> Int
    typealias DateProvider = () -> Date?

    let defaults: UserDefaults
    let clipboardRecordCount: CountProvider
    let downloadRecordCount: CountProvider
    let folderPreviewLastInvoked: DateProvider

    /// Key written by FolderPreview extension on each preview render.
    static let folderPreviewLastInvokedKey = "folderPreview.lastInvokedAt"

    init(
        defaults: UserDefaults = AppGroupSettings.defaults,
        clipboardRecordCount: @escaping CountProvider,
        downloadRecordCount: @escaping CountProvider,
        folderPreviewLastInvoked: @escaping DateProvider = {
            AppGroupSettings.defaults.object(forKey: PriorUsageDetector.folderPreviewLastInvokedKey) as? Date
        }
    ) {
        self.defaults = defaults
        self.clipboardRecordCount = clipboardRecordCount
        self.downloadRecordCount = downloadRecordCount
        self.folderPreviewLastInvoked = folderPreviewLastInvoked
    }

    func detect() throws -> [FeatureID: PriorUsageLevel] {
        var result: [FeatureID: PriorUsageLevel] = [:]
        result[.clipboard] = try detectClipboard()
        result[.downloader] = try detectDownloader()
        result[.voice] = detectVoice()
        result[.folderPreview] = detectFolderPreview()
        result[.windowLayouts] = detectWindowLayouts()
        result[.windowGrab] = detectWindowGrab()
        return result
    }

    // MARK: Per-feature probes

    private func detectClipboard() throws -> PriorUsageLevel {
        if try clipboardRecordCount() > 0 { return .directEvidence }
        // Indirect: any non-default clipboard setting
        if let v = defaults.object(forKey: "retention.maxItems") as? Int, v != 1000 {
            return .indirectEvidence
        }
        if let v = defaults.object(forKey: "retention.maxAgeDays") as? Int, v != 30 {
            return .indirectEvidence
        }
        if defaults.object(forKey: "autoPaste.behavior") != nil { return .indirectEvidence }
        if defaults.object(forKey: "autoPaste.delayMs") != nil { return .indirectEvidence }
        return .none
    }

    private func detectDownloader() throws -> PriorUsageLevel {
        if try downloadRecordCount() > 0 { return .directEvidence }
        // Indirect: any non-default Downloads setting
        if defaults.object(forKey: "downloads.outputTemplate") != nil { return .indirectEvidence }
        if defaults.object(forKey: "downloads.outputDirectory") != nil { return .indirectEvidence }
        if defaults.object(forKey: "downloads.format") != nil { return .indirectEvidence }
        return .none
    }

    private func detectVoice() -> PriorUsageLevel {
        // Direct: VoiceASRSettings persisted (store writes only when user changes anything;
        // default is in-memory only).
        if defaults.data(forKey: "voice.asr.settings.v1") != nil { return .directEvidence }
        // Indirect: any voice-related setting persisted
        if defaults.object(forKey: "voice.activation.hotkey") != nil { return .indirectEvidence }
        if defaults.object(forKey: "voice.groq.apiKey.present") != nil { return .indirectEvidence }
        return .none
    }

    private func detectFolderPreview() -> PriorUsageLevel {
        // Direct: invoked at least once in the last 90 days
        if let last = folderPreviewLastInvoked(), last.timeIntervalSinceNow > -60 * 60 * 24 * 90 {
            return .directEvidence
        }
        // Indirect: non-default settings
        if defaults.object(forKey: "folderPreviewIncludeHidden") != nil,
           defaults.bool(forKey: "folderPreviewIncludeHidden") {
            return .indirectEvidence
        }
        if defaults.object(forKey: "folderPreviewMaxEntries") != nil,
           defaults.integer(forKey: "folderPreviewMaxEntries") != 50_000 {
            return .indirectEvidence
        }
        return .none
    }

    private func detectWindowLayouts() -> PriorUsageLevel {
        guard defaults.data(forKey: WindowControlSettingsStore.key) != nil else { return .none }
        let settings = WindowControlSettingsStore.load(from: defaults)
        return settings.enabled ? .directEvidence : .none
    }

    private func detectWindowGrab() -> PriorUsageLevel {
        guard defaults.data(forKey: WindowControlSettingsStore.key) != nil else { return .none }
        let settings = WindowControlSettingsStore.load(from: defaults)
        return settings.enabled && settings.dragAnywhereEnabled ? .directEvidence : .none
    }
}

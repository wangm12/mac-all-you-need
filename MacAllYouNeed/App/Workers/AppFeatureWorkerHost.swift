import Core
import FeatureCore
import Foundation

/// Main-app registry of per-feature background workers. Started/stopped from `FeatureRuntime`.
@MainActor
final class AppFeatureWorkerHost {
    let clipboard: ClipboardWorker
    let dockPreviews: DockPreviewWorker
    let downloader: DownloadFeatureWorker
    let voice: VoiceFeatureWorker
    let folderPreview: FolderPreviewFeatureWorker
    let folderHistory: FolderHistoryFeatureWorker
    let windowControl: WindowControlFeatureWorker
    let reminders: RemindersFeatureWorker
    let organizer: OrganizerFeatureWorker

    private var running = Set<FeatureID>()

    init(clip: ClipboardStore, search: SearchStore) {
        clipboard = ClipboardWorker(clip: clip, search: search)
        dockPreviews = DockPreviewWorker()
        downloader = DownloadFeatureWorker()
        voice = VoiceFeatureWorker()
        folderPreview = FolderPreviewFeatureWorker()
        folderHistory = FolderHistoryFeatureWorker()
        windowControl = WindowControlFeatureWorker()
        reminders = RemindersFeatureWorker()
        organizer = OrganizerFeatureWorker()
    }

    func startWorker(for id: FeatureID) async {
        switch id {
        case .clipboard, .clipboardSmartText:
            guard !running.contains(.clipboard) else { return }
            await clipboard.start()
            running.insert(.clipboard)
            running.insert(.clipboardSmartText)
        case .dockPreviews:
            guard !running.contains(id) else { return }
            await dockPreviews.start()
            running.insert(id)
        case .downloader:
            guard !running.contains(id) else { return }
            await downloader.start()
            running.insert(id)
        case .voice:
            guard !running.contains(.voice) else { return }
            await voice.start()
            running.insert(.voice)
        case .voiceReminders:
            guard !running.contains(.voice) else {
                running.insert(.voiceReminders)
                return
            }
            await voice.start()
            running.insert(.voice)
            running.insert(.voiceReminders)
        case .folderPreview:
            guard !running.contains(id) else { return }
            await folderPreview.start()
            running.insert(id)
        case .folderHistory:
            guard !running.contains(id) else { return }
            await folderHistory.start()
            running.insert(id)
        case .windowLayouts, .windowGrab:
            guard !running.contains(.windowLayouts) else { return }
            await windowControl.start()
            running.insert(.windowLayouts)
            running.insert(.windowGrab)
        case .aiFileOrganizer:
            guard !running.contains(id) else { return }
            await organizer.start()
            running.insert(id)
        }
    }

    func stopWorker(for id: FeatureID) async {
        switch id {
        case .clipboard, .clipboardSmartText:
            guard running.contains(.clipboard) else { return }
            await clipboard.stop()
            running.remove(.clipboard)
            running.remove(.clipboardSmartText)
        case .dockPreviews:
            guard running.contains(id) else { return }
            await dockPreviews.stop()
            running.remove(id)
        case .downloader:
            guard running.contains(id) else { return }
            await downloader.stop()
            running.remove(id)
        case .voiceReminders:
            running.remove(.voiceReminders)
        case .voice:
            guard running.contains(.voice) else { return }
            await voice.stop()
            running.remove(.voice)
            running.remove(.voiceReminders)
        case .folderPreview:
            guard running.contains(id) else { return }
            await folderPreview.stop()
            running.remove(id)
        case .folderHistory:
            guard running.contains(id) else { return }
            await folderHistory.stop()
            running.remove(id)
        case .windowLayouts, .windowGrab:
            guard running.contains(.windowLayouts) else { return }
            await windowControl.stop()
            running.remove(.windowLayouts)
            running.remove(.windowGrab)
        case .aiFileOrganizer:
            guard running.contains(id) else { return }
            await organizer.stop()
            running.remove(id)
        }
    }

    func deactivateAll() async {
        let ids = Array(running)
        for id in ids {
            await stopWorker(for: id)
        }
    }
}

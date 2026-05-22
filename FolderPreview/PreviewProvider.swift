import Cocoa
import Core
import FeatureCore
import Platform
import Quartz

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let previewView = QuickLookPreviewView()
    private var previewTask: Task<Void, Never>?
    private var previewID = UUID()
    private let featureStateDefaults: UserDefaults

    /// Production initializer — macOS instantiates the principal class via this path.
    /// Reads from the shared App Group defaults.
    convenience init() {
        self.init(featureStateDefaults: UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
    }

    /// Dependency-injection initializer for tests.
    init(featureStateDefaults: UserDefaults) {
        self.featureStateDefaults = featureStateDefaults
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used by Quick Look extensions")
    }

    override func loadView() {
        view = previewView
        preferredContentSize = NSSize(width: 1080, height: 640)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewTask?.cancel()

        // § 3.3 OS-extension policy: the extension is launched by macOS regardless of
        // FeatureManager.activationState, so it self-checks and short-circuits when the
        // feature is disabled. Missing/garbage state defaults to enabled (FeatureStateReader).
        let state = FeatureStateReader.read(for: .folderPreview, defaults: featureStateDefaults)
        if state.activationState == .disabled {
            let placeholder = DisabledPlaceholderRenderer.render()
            previewView.configureDisabledPlaceholder(
                title: placeholder.title,
                body: placeholder.body,
                badge: placeholder.badge
            )
            handler(nil)
            return
        }

        let id = UUID()
        previewID = id

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        previewView.configureLoading(url: url, isDirectory: isDirectory)
        handler(nil)

        previewTask = Task {
            do {
                if isDirectory {
                    let cascade = FolderPreviewSettings.cascadeEnabled()
                    let inventory = try await FolderEnumerator.enumerateImmediate(url: url, maxEntries: 500)
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.previewID == id else { return }
                        previewView.configureFolder(url: url, inventory: inventory, cascade: cascade)
                    }
                } else {
                    let entries = try await Task.detached(priority: .userInitiated) {
                        try LibArchiveBackend().list(archiveURL: url, limits: .default)
                    }.value
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.previewID == id else { return }
                        previewView.configureArchive(url: url, entries: entries)
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard self.previewID == id else { return }
                    previewView.configureError(title: url.lastPathComponent, error: error)
                }
            }
        }
    }

    // MARK: - Test hooks

    struct ChromeSnapshot {
        let title: String
        let subtitle: String
    }

    @MainActor
    func testHook_currentChromeSnapshot() -> ChromeSnapshot {
        previewView.currentChromeSnapshot()
    }
}

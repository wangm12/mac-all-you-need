import AppKit
import Core

@MainActor
final class DockProgressController {
    private weak var vm: DownloaderViewModel?
    private var timer: Timer?

    init(vm: DownloaderViewModel) {
        self.vm = vm
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        observeActiveCount()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // Watches vm.rows for a 0→1 active-download transition and restarts the
    // timer if it was previously stopped due to going idle.
    private func observeActiveCount() {
        guard let vm else { return }
        withObservationTracking {
            _ = vm.rows.filter { $0.state == .running }.count
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleActiveCountChange()
            }
        }
    }

    private func handleActiveCountChange() {
        guard let vm else { return }
        let activeCount = vm.rows.filter { $0.state == .running }.count
        if activeCount > 0 {
            start() // idempotent — only schedules if timer == nil
        }
        // Re-arm the observation for the next change.
        observeActiveCount()
    }

    private func tick() {
        guard let vm else { return }
        let active = vm.rows.filter { $0.state == .running }
        guard !active.isEmpty else {
            NSApp.dockTile.badgeLabel = ""
            NSApp.dockTile.display()
            stop()
            return
        }
        let fractions = active.compactMap { vm.liveProgress[$0.id.rawValue]?.fraction }
        let avg = fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
        NSApp.dockTile.badgeLabel = "\(Int(avg * 100))%"
        NSApp.dockTile.display()
    }
}

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    private func tick() {
        guard let vm else { return }
        let active = vm.rows.filter { $0.state == .running }
        guard !active.isEmpty else {
            NSApp.dockTile.badgeLabel = ""
            NSApp.dockTile.display()
            return
        }
        let fractions = active.compactMap { vm.liveProgress[$0.id.rawValue]?.fraction }
        let avg = fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
        NSApp.dockTile.badgeLabel = "\(Int(avg * 100))%"
        NSApp.dockTile.display()
    }
}

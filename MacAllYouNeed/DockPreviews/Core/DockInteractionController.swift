import ApplicationServices
import Foundation
import Platform

/// AX dock hover observer facade (DockDoor `DockObserver` hover path).
@MainActor
final class DockInteractionController {
    private let observer: DockHoverObserver
    var onHoverBegan: ((DockHoverTarget) -> Void)?
    var onHoverEnded: (() -> Void)?

    init(axCoordinator: AXObserverCoordinator) {
        observer = DockHoverObserver(coordinator: axCoordinator)
        observer.onHoverBegan = { [weak self] target in self?.onHoverBegan?(target) }
        observer.onHoverEnded = { [weak self] in self?.onHoverEnded?() }
    }

    var settingsProvider: () -> DockPreviewSettings {
        get { observer.settings }
        set { observer.settings = newValue }
    }

    func start() { observer.start() }
    func stop() { observer.stop() }
}

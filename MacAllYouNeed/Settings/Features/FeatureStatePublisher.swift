import Combine
import FeatureCore
import Foundation

/// Mirrors FeatureManager state into a Published dict that SwiftUI can observe.
/// FeatureManager is an actor (writes are async); UI needs synchronous reads.
/// This class is the bridge.
@MainActor
final class FeatureStatePublisher: ObservableObject {
    @Published private(set) var states: [FeatureID: FeatureRuntimeState] = [:]
    private let manager: FeatureManager

    init(manager: FeatureManager) {
        self.manager = manager
        Task { await self.refresh() }
        NotificationCenter.default.addObserver(
            forName: .featureRuntimeStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        let snapshot = await manager.allStates()
        states = snapshot
    }

    func state(for id: FeatureID) -> FeatureRuntimeState {
        states[id] ?? .initialDefault(assetRequired: false)
    }
}

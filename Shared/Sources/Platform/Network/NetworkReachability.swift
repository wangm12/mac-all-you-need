import Foundation
import Network

/// Observes the device's network path and exposes a simple `isOnline` flag.
/// Updates are delivered on the main actor.
@MainActor
public final class NetworkReachability: ObservableObject {
    public static let shared = NetworkReachability()

    @Published public private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.macallyouneed.network.reachability", qos: .utility)

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}

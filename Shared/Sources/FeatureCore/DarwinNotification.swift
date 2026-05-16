import Foundation

public enum DarwinNotification {
    public static let featureStateDidChange = "com.macallyouneed.featureStateDidChange"

    public static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = CFNotificationName(rawValue: name as CFString)
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }
}

public extension Notification.Name {
    /// Posted on NotificationCenter.default after every feature state transition.
    /// Used by FeatureStatePublisher to refresh its @Published mirror.
    static let featureRuntimeStateChanged = Notification.Name("featureRuntimeStateChanged")
}

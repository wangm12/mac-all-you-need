import CoreFoundation
import Core
import SwiftUI

enum ClipboardCleanupThreshold: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            "Day"
        case .week:
            "Week"
        case .month:
            "Month"
        case .never:
            "Never"
        }
    }

    var days: Int? {
        switch self {
        case .day:
            1
        case .week:
            7
        case .month:
            30
        case .never:
            nil
        }
    }
}

struct StorageSettingsView: View {
    @State private var maxItems: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxItems") as? Int) ?? 1000
    @State private var maxAgeDays: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxAgeDays") as? Int) ?? 30
    @State private var maxImageMB: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxImageMB") as? Int) ?? 200
    @State private var cleanupThreshold: ClipboardCleanupThreshold = .never

    var body: some View {
        MAYNSettingsPage(
            title: "Storage",
            subtitle: "Set retention limits and run one-time clipboard history cleanup."
        ) {
            MAYNSection(title: "History size") {
                MAYNSettingsRow(
                    title: "Maximum items",
                    subtitle: "Keep clipboard history bounded before retention cleanup runs."
                ) {
                    MAYNNumericStepper(
                        text: "\(maxItems)",
                        value: $maxItems,
                        range: 100...10_000,
                        step: 100,
                        presets: [500, 1_000, 5_000, 10_000]
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Maximum age",
                    subtitle: "Old entries are eligible for cleanup after this duration."
                ) {
                    MAYNDropdown(
                        selection: $maxAgeDays,
                        options: [0, 7, 30, 90, 365],
                        title: maxAgeTitle
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Image storage",
                    subtitle: "Use 0 MB to allow unlimited image blob storage."
                ) {
                    MAYNNumericStepper(
                        text: "\(maxImageMB) MB",
                        value: $maxImageMB,
                        range: 0...2_000,
                        step: 50,
                        presets: [0, 100, 250, 500, 1_000, 2_000],
                        suffix: "MB"
                    )
                }
            }

            MAYNSection(
                title: "Maintenance",
                subtitle: "Run a one-time cleanup for older clipboard history."
            ) {
                MAYNSettingsRow(
                    title: "Clear clipboard history",
                    subtitle: "Choose how far back to keep before clearing older entries."
                ) {
                    MAYNDropdown(
                        selection: $cleanupThreshold,
                        options: Array(ClipboardCleanupThreshold.allCases),
                        title: { $0.title }
                    )
                }
            }
        }
        .onChange(of: maxItems) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "retention.maxItems")
            postSettingsChangedDarwin()
        }
        .onChange(of: maxAgeDays) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "retention.maxAgeDays")
            postSettingsChangedDarwin()
        }
        .onChange(of: maxImageMB) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "retention.maxImageMB")
            postSettingsChangedDarwin()
        }
        .onChange(of: cleanupThreshold) { _, value in
            guard let days = value.days else { return }
            NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: days)
        }
    }

    private func postSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    private func maxAgeTitle(_ days: Int) -> String {
        switch days {
        case 0:
            "Forever"
        case 1:
            "1 day"
        default:
            "\(days) days"
        }
    }
}

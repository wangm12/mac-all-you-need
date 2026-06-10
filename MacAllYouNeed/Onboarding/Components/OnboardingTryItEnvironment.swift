import AVFoundation
import SwiftUI

private struct OnboardingTryItSucceededKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

private struct OnboardingRequiresTryItKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var onboardingTryItSucceeded: Binding<Bool>? {
        get { self[OnboardingTryItSucceededKey.self] }
        set { self[OnboardingTryItSucceededKey.self] = newValue }
    }

    var onboardingRequiresTryIt: Bool {
        get { self[OnboardingRequiresTryItKey.self] }
        set { self[OnboardingRequiresTryItKey.self] = newValue }
    }
}

/// Marks onboarding try-it complete when the binding is present.
@MainActor
enum OnboardingTryItReporter {
    static func markSucceeded(_ binding: Binding<Bool>?) {
        binding?.wrappedValue = true
    }
}

enum OnboardingPermissionCTAVisibility {
    static func shouldShowMicrophoneCTA() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
    }
}

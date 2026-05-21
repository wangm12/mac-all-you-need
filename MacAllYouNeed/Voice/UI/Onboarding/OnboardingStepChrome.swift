import AppKit

/// Shared helper used by multiple onboarding step views.
func openSystemSettings(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
}

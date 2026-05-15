import Foundation

enum VoicePersonalizationPrivacyFilter {
    static let editableTextRoleAllowlist: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox"
    ]

    static let secureSubrole = "AXSecureTextField"

    /// Bundle identifiers that always reject capture even if AX role passes.
    /// Primarily covers password managers and Keychain UI. The list is best-effort;
    /// the role allowlist + AXSecureTextField subrole are the primary safety mechanisms.
    static let bundleDenyList: Set<String> = [
        // 1Password
        "com.1password.1password",
        "com.1password.1password7",
        "com.1password.macos",
        "com.1password.8",
        // Bitwarden
        "com.bitwarden.desktop",
        // Dashlane
        "com.dashlane.dashlanephonefinal",
        "com.dashlane.macapp",
        // LastPass
        "com.lastpass.LastPass",
        // NordPass
        "com.nordvpn.nordpass",
        // Proton Pass
        "ch.protonmail.pass",
        // System Keychain / auth UIs
        "com.apple.keychainaccess",
        "com.apple.SecurityAgent"
    ]

    static func shouldCapture(_ metadata: AXTargetMetadata) -> Bool {
        guard let bundleID = metadata.bundleID, !bundleID.isEmpty else { return false }
        guard !bundleDenyList.contains(bundleID) else { return false }
        guard let role = metadata.role, editableTextRoleAllowlist.contains(role) else { return false }
        if metadata.subrole == secureSubrole { return false }
        guard metadata.isEditable else { return false }
        return true
    }
}

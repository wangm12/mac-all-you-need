import Foundation

public struct CookieImportResult: Sendable {
    public let hadErrors: Bool
}

public struct CookieImportOptions: Sendable {
    public let preferredBrowser: BrowserProfile.Browser?
    public let includeSafari: Bool
    public let appendExistingCookieFile: URL?

    public init(
        preferredBrowser: BrowserProfile.Browser? = nil,
        includeSafari: Bool = true,
        appendExistingCookieFile: URL? = nil
    ) {
        self.preferredBrowser = preferredBrowser
        self.includeSafari = includeSafari
        self.appendExistingCookieFile = appendExistingCookieFile
    }
}

public enum CookieImporter {
    @discardableResult
    public static func combinedCookiesFile(
        at url: URL,
        options: CookieImportOptions = CookieImportOptions()
    ) throws -> CookieImportResult {
        var combined = "# Netscape HTTP Cookie File\n"
        var hadErrors = false
        let chromiumProfiles = ChromiumCookies.discoverProfiles().filter { profile in
            guard let preferred = options.preferredBrowser else { return true }
            return profile.browser == preferred
        }
        for profile in chromiumProfiles {
            do {
                combined += try ChromiumCookies.exportNetscape(profile: profile)
            } catch {
                hadErrors = true
            }
        }
        if options.includeSafari,
           (options.preferredBrowser == nil || options.preferredBrowser == .safari),
           let safariProfile = SafariCookies.discoverStore(),
           let s = try? SafariCookies.exportNetscape(profile: safariProfile)
        {
            combined += s
        }
        if let appendPath = options.appendExistingCookieFile,
           FileManager.default.fileExists(atPath: appendPath.path),
           let existing = try? String(contentsOf: appendPath, encoding: .utf8),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            combined += "\n"
            combined += existing
            if !combined.hasSuffix("\n") {
                combined += "\n"
            }
        }
        try combined.write(to: url, atomically: true, encoding: .utf8)
        return CookieImportResult(hadErrors: hadErrors)
    }
}

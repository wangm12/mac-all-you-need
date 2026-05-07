import Foundation

public struct CookieImportResult: Sendable {
    public let hadErrors: Bool
}

public enum CookieImporter {
    @discardableResult
    public static func combinedCookiesFile(at url: URL) throws -> CookieImportResult {
        var combined = "# Netscape HTTP Cookie File\n"
        var hadErrors = false
        for profile in ChromiumCookies.discoverProfiles() {
            do {
                combined += try ChromiumCookies.exportNetscape(profile: profile)
            } catch {
                hadErrors = true
            }
        }
        if let safariProfile = SafariCookies.discoverStore(),
           let s = try? SafariCookies.exportNetscape(profile: safariProfile)
        {
            combined += s
        }
        try combined.write(to: url, atomically: true, encoding: .utf8)
        return CookieImportResult(hadErrors: hadErrors)
    }
}

import Foundation

public enum CookieImporter {
    public static func combinedCookiesFile(at url: URL) throws {
        var combined = "# Netscape HTTP Cookie File\n"
        for p in ChromiumCookies.discoverProfiles() {
            if let s = try? ChromiumCookies.exportNetscape(profile: p) { combined += s }
        }
        if let safariProfile = SafariCookies.discoverStore() {
            if let s = (try? SafariCookies.exportNetscape(profile: safariProfile)) ?? nil {
                combined += s
            }
        }
        try combined.write(to: url, atomically: true, encoding: .utf8)
    }
}

import Foundation

public enum SafariCookies {
    public static func discoverStore() -> BrowserProfile? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return BrowserProfile(browser: .safari, name: "Default", cookieDB: nil, safariBinaryStore: url)
    }

    public static func exportNetscape(profile _: BrowserProfile) throws -> String? {
        nil // Safari binarycookies parsing deferred to v2
    }
}

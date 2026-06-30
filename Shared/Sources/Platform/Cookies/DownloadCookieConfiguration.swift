import Core
import Foundation

public enum DownloadCookieConfiguration {
    public struct Result: Sendable {
        public let args: [String]
        public let hadErrors: Bool
        public let cookieFileURL: URL?

        public init(args: [String], hadErrors: Bool, cookieFileURL: URL? = nil) {
            self.args = args
            self.hadErrors = hadErrors
            self.cookieFileURL = cookieFileURL
        }
    }

    public static func cookieDirectory() -> URL {
        AppGroup.containerURL().appendingPathComponent("cookies", isDirectory: true)
    }

    public static func combinedCookieFileURL() -> URL {
        cookieDirectory().appendingPathComponent("downloader-cookies.txt")
    }

    public static func extensionCookieFileURL() -> URL {
        cookieDirectory().appendingPathComponent("downloader-extension-cookies.txt")
    }

    public static func preferredBrowserProfile(for raw: String) -> BrowserProfile.Browser? {
        switch raw {
        case "chrome", "chromium":
            .chrome
        case "edge":
            .edge
        case "brave":
            .brave
        case "safari":
            .safari
        default:
            nil
        }
    }

    public static func makeCookieArgs() -> (args: [String], hadErrors: Bool) {
        let result = makeCookieConfiguration()
        return (result.args, result.hadErrors)
    }

    public static func makeCookieConfiguration() -> Result {
        let cookieFile = combinedCookieFileURL()
        let extensionCookieFile = extensionCookieFileURL()
        let cookieMode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode") ?? "browser_auto"
        do {
            try FileManager.default.createDirectory(
                at: cookieDirectory(),
                withIntermediateDirectories: true
            )
            if cookieMode == "extension_only" {
                let exists = FileManager.default.fileExists(atPath: extensionCookieFile.path)
                return Result(
                    args: exists ? ["--cookies", extensionCookieFile.path] : [],
                    hadErrors: !exists,
                    cookieFileURL: exists ? extensionCookieFile : nil
                )
            }
            let browserPref = AppGroupSettings.defaults.string(forKey: "downloadCookieBrowserProfile") ?? "chrome"
            let preferredBrowser = preferredBrowserProfile(for: browserPref)
            let options = CookieImportOptions(
                preferredBrowser: preferredBrowser,
                includeSafari: preferredBrowser == nil || preferredBrowser == .safari,
                appendExistingCookieFile: extensionCookieFile
            )
            let importResult = try CookieImporter.combinedCookiesFile(at: cookieFile, options: options)
            return Result(
                args: ["--cookies", cookieFile.path],
                hadErrors: importResult.hadErrors,
                cookieFileURL: cookieFile
            )
        } catch {
            return Result(args: [], hadErrors: true)
        }
    }

    /// Best-effort cookie args for bulk enqueue (mirrors legacy prepareBulkConfiguration behavior).
    public static func bulkCookieArgs() -> [String] {
        let cookieFile = combinedCookieFileURL()
        let extensionCookieFile = extensionCookieFileURL()
        let cookieMode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode") ?? "browser_auto"
        if cookieMode == "extension_only" {
            if FileManager.default.fileExists(atPath: extensionCookieFile.path) {
                return ["--cookies", extensionCookieFile.path]
            }
            return []
        }
        let browserPref = AppGroupSettings.defaults.string(forKey: "downloadCookieBrowserProfile") ?? "chrome"
        let preferredBrowser = preferredBrowserProfile(for: browserPref)
        let options = CookieImportOptions(
            preferredBrowser: preferredBrowser,
            includeSafari: preferredBrowser == nil || preferredBrowser == .safari,
            appendExistingCookieFile: extensionCookieFile
        )
        _ = try? CookieImporter.combinedCookiesFile(at: cookieFile, options: options)
        return ["--cookies", cookieFile.path]
    }
}

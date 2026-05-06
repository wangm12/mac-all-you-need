import Foundation

public struct BrowserProfile: Equatable, Sendable {
    public enum Browser: String, Sendable { case chrome, edge, brave, arc, safari }
    public let browser: Browser
    public let name: String
    public let cookieDB: URL?
    public let safariBinaryStore: URL?
}

import CoreGraphics

public enum AppKitWindowIdentifier {
    public static func matches(windowNumber: Int, cgWindowID: CGWindowID) -> Bool {
        guard windowNumber > 0,
              let candidate = CGWindowID(exactly: windowNumber)
        else {
            return false
        }
        return candidate == cgWindowID
    }
}

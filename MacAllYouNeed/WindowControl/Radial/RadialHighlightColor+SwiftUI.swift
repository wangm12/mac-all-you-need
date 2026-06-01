import AppKit
import Core
import SwiftUI

extension RadialHighlightColor {
  /// User-configurable desktop overlay color (design.md §10.8), not app chrome.
    var swiftUIColor: Color {
        Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
    }
}

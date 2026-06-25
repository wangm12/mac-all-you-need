import Foundation

/// URL heuristics for routing Douyin extension / play-API dispatches through the native resolver.
public enum DouyinDownloadURLPatterns {
  public static func prefersNativeResolve(url: String) -> Bool {
    let lower = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lower.isEmpty else { return false }
    if lower.contains("douyin.com/video/") { return true }
    if lower.contains("douyin.com/note/") { return true }
    if lower.contains("v.douyin.com/") { return true }
    if lower.contains("douyin.com/aweme/v1/play") { return true }
    if lower.contains("iesdouyin.com") { return true }
    return false
  }

  /// Extension titles use `author — description — awemeId` (optional trailing format suffix).
  public static func extractAwemeIDFromTitle(_ title: String?) -> String? {
    guard let title, !title.isEmpty else { return nil }
    for part in title.components(separatedBy: " — ").reversed() {
      let digits = part.trimmingCharacters(in: .whitespacesAndNewlines)
      guard digits.count >= 10, digits.allSatisfy(\.isNumber) else { continue }
      return digits
    }
    return nil
  }
}

import AppKit
import Foundation

/// Builds the content shown when the Folder Preview feature is disabled.
/// Returns a plain title string and an `NSAttributedString` body so the caller
/// can route them into the existing chrome without redesigning the view.
enum DisabledPlaceholderRenderer {
    struct PlaceholderContent {
        let title: String
        let body: NSAttributedString
        let badge: String
    }

    static func render() -> PlaceholderContent {
        let title = "Folder Preview is disabled"

        let bodyText =
            "Open Mac All You Need → Settings → Features to re-enable Folder Preview.\n\n" +
            "The Quick Look extension stays installed with the app, so this placeholder " +
            "appears whenever you press Space on a folder while the feature is off."

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 8
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        return PlaceholderContent(
            title: title,
            body: NSAttributedString(string: bodyText, attributes: attributes),
            badge: "Disabled"
        )
    }
}

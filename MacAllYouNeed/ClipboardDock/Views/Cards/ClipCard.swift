import AppKit
import Core
import Platform
import SwiftUI

struct ClipCard: View {
    let item: DockItem
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let fileThumbnailLoader: FileThumbnailLoader
    let favicons: FaviconCache
    let cardBackground: Color
    /// When true, `CardSlot` shows the ⌘1…⌘9 chip over the bottom-leading corner;
    /// the smart-text footer indents so labels clear that overlay.
    var showsPasteShortcutChip: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var appAccent: Color {
        ClipCardAccentPresentation.accent(for: item)
    }

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(item: item, appAccent: appAccent)
            cardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if item.smartCopyValue != nil {
                SmartTextFooter(
                    item: item,
                    appAccent: appAccent,
                    showsPasteShortcutChip: showsPasteShortcutChip
                )
            }
        }
        .background {
            cardBackground
                .overlay(appAccent.opacity(ClipCardAccentPresentation.cardTintOpacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.kind {
        case .text, .rtf:
            TextCard(item: item)
        case .image:
            ImageCard(item: item, loader: imageLoader)
        case .file:
            FileCard(
                item: item,
                loader: fileLoader,
                thumbnailLoader: fileThumbnailLoader
            )
        case .link:
            LinkCard(item: item, favicons: favicons)
        case .color:
            ColorCard(item: item)
        case .code:
            CodeCard(item: item)
        }
    }
}

/// Paste-style header: kind label + relative timestamp on the left,
/// source app icon on the right.
private struct CardHeader: View {
    let item: DockItem
    let appAccent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kindLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(timestampText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            appIcon
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            MAYNTheme.elevated
                .overlay(appAccent.opacity(ClipCardAccentPresentation.headerTintOpacity))
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let app = item.sourceApp, let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(appAccent.opacity(ClipCardAccentPresentation.iconStrokeOpacity), lineWidth: 1)
                )
                .help(app.displayName)
        } else {
            Circle()
                .fill(appAccent.opacity(0.22))
                .frame(width: 8, height: 8)
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .text:
            return "Text"
        case .rtf:
            return "Rich Text"
        case .image(let w, let h, _):
            if w > 0 && h > 0 { return "Image · \(w)×\(h)" }
            return "Image"
        case .file(let count):
            return count > 1 ? "\(count) files" : "File"
        case .link:
            return "Link"
        case .color:
            return "Color"
        case .code(let language):
            return "Code · \(language)"
        }
    }

    private var timestampText: String {
        Self.relativeFormatter.localizedString(for: item.modified, relativeTo: Date())
    }

    /// Static so we don't construct a new formatter every render — Foundation
    /// formatters are heavyweight to allocate.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

/// Dedicated footer strip shown when a card has a Smart Text result.
/// Clearly labels the type (calculation / cleaned link / OCR) and provides a Copy button.
private struct SmartTextFooter: View {
    let item: DockItem
    let appAccent: Color
    let showsPasteShortcutChip: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var copyPressPulse = false

    private var label: String {
        if item.calculation != nil { return "= \(item.calculation!.value)" }
        if item.trackerCount > 0   { return "\(item.trackerCount) tracker\(item.trackerCount == 1 ? "" : "s") removed" }
        if item.hasOCRText         { return "Text recognized" }
        return "Smart Text"
    }

    private var reduceMotion: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
            copyButton
        }
        .padding(.leading, 10 + (showsPasteShortcutChip ? DockCardShellPresentation.pasteShortcutChipGutter : 0))
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            appAccent.opacity(0.72)
        }
    }

    private var copyButton: some View {
        Button {
            guard let value = item.smartCopyValue else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(value, forType: .string)
            pb.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
            CopyHUD.show("Smart copied", symbol: "sparkles")
            playCopyPressedFeedback()
        } label: {
            Text("Copy")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(copyPressPulse ? 0.32 : 0.18))
                )
                .scaleEffect(copyPressPulse && !reduceMotion ? 0.93 : 1)
        }
        .buttonStyle(.borderless)
        .animation(MAYNMotion.animation(.press, reduceMotion: reduceMotion), value: copyPressPulse)
    }

    private func playCopyPressedFeedback() {
        let step = MAYNMotionDuration.press
        if reduceMotion {
            copyPressPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + step) {
                copyPressPulse = false
            }
            return
        }
        copyPressPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + step) {
            copyPressPulse = false
        }
    }
}

enum ClipCardAccentPresentation {
    static let topAccentHeight: CGFloat = 0
    static let cardTintOpacity = 0.18
    static let headerTintOpacity = 0.34
    static let dividerAccentOpacity = 0
    static let iconStrokeOpacity = 0.52
    static let fallbackAccent = Color.secondary
    private static let palette: [(key: String, color: NSColor)] = [
        ("blue", NSColor(srgbRed: 0.02, green: 0.33, blue: 0.92, alpha: 1.0)),
        ("emerald", NSColor(srgbRed: 0.00, green: 0.48, blue: 0.30, alpha: 1.0)),
        ("violet", NSColor(srgbRed: 0.38, green: 0.18, blue: 0.88, alpha: 1.0)),
        ("orange", NSColor(srgbRed: 0.92, green: 0.34, blue: 0.02, alpha: 1.0)),
        ("magenta", NSColor(srgbRed: 0.82, green: 0.05, blue: 0.40, alpha: 1.0)),
        ("teal", NSColor(srgbRed: 0.00, green: 0.48, blue: 0.60, alpha: 1.0)),
        ("amber", NSColor(srgbRed: 0.82, green: 0.48, blue: 0.00, alpha: 1.0)),
        ("indigo", NSColor(srgbRed: 0.12, green: 0.20, blue: 0.78, alpha: 1.0)),
        ("red", NSColor(srgbRed: 0.82, green: 0.12, blue: 0.16, alpha: 1.0)),
        ("mint", NSColor(srgbRed: 0.00, green: 0.56, blue: 0.42, alpha: 1.0)),
        ("purple", NSColor(srgbRed: 0.56, green: 0.18, blue: 0.72, alpha: 1.0)),
        ("brown", NSColor(srgbRed: 0.54, green: 0.30, blue: 0.12, alpha: 1.0))
    ]
    private static let knownAccentKeys: [String: String] = [
        "com.google.chrome": "blue",
        "com.openai.codex": "violet",
        "com.openai.chat": "violet",
        "com.openai.chatgpt": "violet",
        "com.tinyspeck.slackmacgap": "magenta",
        "com.apple.dt.xcode": "orange",
        "com.todesktop.230313mzl4w4u92": "amber",
        "com.microsoft.vscode": "indigo",
        "com.apple.finder": "teal",
        "com.apple.safari": "blue",
        "com.apple.terminal": "emerald",
        "com.googlecode.iterm2": "emerald",
        "company.thebrowser.browser": "purple",
        "com.microsoft.edgemac": "mint",
        "com.brave.browser": "orange",
        "com.apple.notes": "amber",
        "org.mozilla.firefox": "orange"
    ]

    static func shouldShowSourceAccent(hasSourceAppIcon: Bool) -> Bool {
        hasSourceAppIcon
    }

    static func stableAccentKey(forBundleID bundleID: String?) -> String {
        guard let bundleID, !bundleID.isEmpty else { return "fallback" }
        let normalized = bundleID.lowercased()
        if let known = knownAccentKeys[normalized] {
            return known
        }
        return palette[stablePaletteIndex(for: normalized)].key
    }

    /// Known bundle IDs and a stable 12-color palette first; then icon extraction.
    static func accent(for item: DockItem) -> Color {
        if let bundleID = item.sourceApp?.bundleID,
           let color = stableAccentColor(forBundleID: bundleID)
        {
            return Color(nsColor: color)
        }

        guard let icon = item.sourceApp?.icon,
              let color = AppIconColor.dominant(of: icon)?.usingColorSpace(.sRGB)
        else {
            return fallbackAccent
        }
        return Color(nsColor: color)
    }

    private static func stableAccentColor(forBundleID bundleID: String?) -> NSColor? {
        let key = stableAccentKey(forBundleID: bundleID)
        return palette.first(where: { $0.key == key })?.color
    }

    private static func stablePaletteIndex(for normalizedBundleID: String) -> Int {
        var hash = 2_166_136_261
        for scalar in normalizedBundleID.unicodeScalars {
            hash = (hash ^ Int(scalar.value)) &* 16_777_619
        }
        return abs(hash) % palette.count
    }
}

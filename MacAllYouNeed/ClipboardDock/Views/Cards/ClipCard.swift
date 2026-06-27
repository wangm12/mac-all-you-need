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
    var isHighlighted: Bool = false
    /// When true, `CardSlot` shows the ⌘1…⌘9 chip over the bottom-leading corner;
    /// the smart-text footer indents so labels clear that overlay.
    var showsPasteShortcutChip: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var appAccent: Color {
        ClipCardAccentPresentation.accent(for: item)
    }

    private var cardTintOpacity: CGFloat {
        isHighlighted ? 0 : ClipCardAccentPresentation.cardTintOpacity
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
                .overlay(appAccent.opacity(cardTintOpacity))
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
    static let cardTintOpacity = 0.14
    static let headerTintOpacity = 0.22
    static let dividerAccentOpacity = 0
    static let iconStrokeOpacity = 0.36
    static let fallbackAccent = Color.secondary

    static func shouldShowSourceAccent(hasSourceAppIcon: Bool) -> Bool {
        hasSourceAppIcon
    }

    /// Card/header tint derived from the source app icon — not a hardcoded palette.
    static func accent(for item: DockItem) -> Color {
        guard let icon = item.sourceApp?.icon,
              let color = AppIconColor.dominant(of: icon)?.usingColorSpace(.sRGB)
        else {
            return fallbackAccent
        }
        return Color(nsColor: color)
    }
}

import AppKit
import SwiftUI

struct DownloadPickerEntryRow: View {
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let trailingID: String
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? MAYNTheme.progress : .secondary)

                thumbnailView

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(trailingID)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 88, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnailURL {
                DownloadPickerThumbnailImage(url: thumbnailURL)
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            MAYNTheme.elevated
            Image(systemName: "play.rectangle")
                .foregroundStyle(.secondary)
        }
    }

    private var background: Color {
        if isSelected { return MAYNTheme.selected }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }

    private var border: Color {
        if isSelected { return MAYNTheme.tabSelectedBorder }
        return isHovering ? MAYNTheme.subtleBorder : .clear
    }
}

private struct DownloadPickerThumbnailImage: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    MAYNTheme.elevated
                    ProgressView().scaleEffect(0.6)
                }
            }
        }
        .task(id: url.absoluteString) {
            image = await load()
        }
    }

    private func load() async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if isDouyinThumbnail(url: url) {
            request.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private func isDouyinThumbnail(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("douyin")
            || host.contains("bytedance")
            || host.contains("toutiao")
            || host.contains("snssdk")
            || host.contains("amemv")
    }
}

enum DownloadPickerDurationFormatting {
    static func format(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%d:%02d", minutes, remaining)
    }
}

import SwiftUI

struct DownloadPickerSheetChrome<Content: View, Toolbar: View, Footer: View>: View {
    let title: String
    let sourceURL: String
    let onClose: () -> Void
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            header
            MAYNDivider()
            toolbar()
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            MAYNDivider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MAYNDivider()
            footer()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(MAYNTheme.elevated)
        }
        .frame(width: 740, height: 660)
        .background(MAYNTheme.window)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text("Choose what to add from this source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sourceURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: MAYNControlMetrics.controlHeight, height: MAYNControlMetrics.controlHeight)
                    .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(MAYNTheme.elevated)
    }
}

struct DownloadPickerStatusBanner: View {
    let text: String

    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

struct DownloadPickerErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MAYNTheme.warning)
                .padding(.top, 1)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

struct DownloadPickerToolbarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

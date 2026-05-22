import SwiftUI

struct VoiceAPIKeySection: View {
    @Binding var isExpanded: Bool
    let providerKind: VoiceASRProviderKind
    @Binding var apiKey: String
    let isTesting: Bool
    let statusMessage: String?
    let testConnection: () -> Void

    var body: some View {
        VoiceCloudASRSetupDrawer(
            isExpanded: $isExpanded,
            providerKind: providerKind,
            apiKey: $apiKey,
            isTesting: isTesting,
            statusMessage: statusMessage,
            testConnection: testConnection
        )
    }
}

// MARK: - Cloud ASR setup drawer

struct VoiceCloudASRSetupDrawer: View {
    @Binding var isExpanded: Bool
    let providerKind: VoiceASRProviderKind
    @Binding var apiKey: String
    let isTesting: Bool
    let statusMessage: String?
    let testConnection: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                drawerContent
            }
        }
        .animation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion), value: isExpanded)
    }

    private var header: some View {
        Button {
            withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VoiceCloudASRSetupDrawerPresentation.title(for: providerKind))
                        .font(.callout)
                    Text(VoiceCloudASRSetupDrawerPresentation.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    StatusPill(text: setupStatus.text, kind: setupStatus.kind.statusPillKind)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 14, height: 14)
                }
                .frame(minWidth: MAYNControlMetrics.trailingLaneMinWidth, alignment: .trailing)
            }
            .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
            .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
            .frame(minHeight: MAYNControlMetrics.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? MAYNTheme.hover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(VoiceCloudASRSetupDrawerPresentation.title(for: providerKind))
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var drawerContent: some View {
        VStack(spacing: 0) {
            MAYNDivider()
            MAYNSettingsRow(title: providerKind.apiKeyLabel) {
                MAYNSecureField(
                    placeholder: providerKind.apiKeyPlaceholder,
                    text: $apiKey,
                    width: MAYNControlMetrics.wideTextFieldWidth
                )
            }
            if let actionTitle = VoiceASRProviderControlsPresentation.connectionActionTitle(for: providerKind) {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Connection",
                    subtitle: "Test after adding or changing the API key."
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        MAYNButton(isTesting ? "Testing..." : actionTitle) {
                            testConnection()
                        }
                        .disabled(isTesting)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    private var setupStatus: VoiceCloudASRSetupStatusPresentation {
        VoiceCloudASRSetupDrawerPresentation.status(
            apiKey: apiKey,
            isTesting: isTesting,
            statusMessage: statusMessage
        )
    }
}

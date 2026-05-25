import AppKit
import Core
import Platform
import SwiftUI

/// Command Center Voice tab: transcript history only (copy + retry per row).
/// Keyboard: arrows to move selection, Space to preview, Return to copy, double-click row to copy
/// (same model as the main Voice History tab).
struct VoicePopoverView: View {
    let controller: AppController

    @State private var transcripts: [VoiceTranscript] = []
    @State private var selectedTranscriptIDs: Set<String> = []
    @State private var transcriptAnchorID: String?
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if transcripts.isEmpty {
                ContentUnavailableView(
                    "No transcripts yet",
                    systemImage: "waveform",
                    description: Text("Completed dictations appear here after transcription.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(transcripts, id: \.id) { transcript in
                            VoiceTranscriptHistoryRowView(
                                transcript: transcript,
                                surface: .commandCenter,
                                isSelected: selectedTranscriptIDs.contains(transcript.id),
                                onSelect: { selectTranscript(transcript) },
                                onCopy: { copyTranscripts(ids: [transcript.id]) },
                                onRetry: { retryTranscript(transcript) },
                                onDownload: {},
                                onDelete: {}
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MAYNTheme.window)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress { handleKeyPress($0) }
        .onAppear {
            listFocused = true
            reloadTranscripts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceTranscriptAppended)) { _ in
            reloadTranscripts()
        }
    }

    private var voiceTranscriptIDs: [String] {
        transcripts.map(\.id)
    }

    private func reloadTranscripts() {
        transcripts = controller.listRecentVoiceTranscripts(limit: 200)
        pruneSelection()
    }

    private func pruneSelection() {
        let existing = Set(transcripts.map(\.id))
        selectedTranscriptIDs.formIntersection(existing)
        if let transcriptAnchorID, !existing.contains(transcriptAnchorID) {
            self.transcriptAnchorID = selectedTranscriptIDs.first ?? transcripts.first?.id
        }
    }

    private func selectTranscript(_ transcript: VoiceTranscript) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let state = MainVoiceTranscriptHistoryPresentation.selection(
            afterClicking: transcript.id,
            orderedIDs: voiceTranscriptIDs,
            selectedIDs: selectedTranscriptIDs,
            anchorID: transcriptAnchorID,
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift)
        )
        selectedTranscriptIDs = state.selectedIDs
        transcriptAnchorID = state.anchorID
    }

    private func effectiveTranscriptIDs() -> [String] {
        MainVoiceTranscriptHistoryPresentation.effectiveIDs(
            selectedIDs: selectedTranscriptIDs,
            anchorID: transcriptAnchorID,
            orderedIDs: voiceTranscriptIDs
        )
    }

    private func copyTranscripts(ids: [String]) {
        let strings = ids.compactMap { id in
            transcripts.first { $0.id == id }.map(MainVoiceTranscriptHistoryPresentation.displayText)
        }.filter { $0 != "Empty transcript" }
        guard !strings.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        CopyHUD.show(strings.count == 1 ? "Copied" : "Copied \(strings.count)")
    }

    private func previewTranscript(id: String?, direction: PreviewPanelTransitionDirection = .none) {
        guard let id,
              let transcript = transcripts.first(where: { $0.id == id })
        else { return }

        PreviewPanel.show(
            .text(MainVoiceTranscriptHistoryPresentation.displayText(transcript), monospaced: false),
            metadata: PreviewPanelMetadata(
                title: "Voice transcript",
                subtitle: "\(CompactTimestamp.format(transcript.endedAt)) · \(transcript.language.rawValue)",
                badge: "\(transcript.durationMs) ms",
                symbol: "waveform"
            ),
            direction: direction
        )
    }

    private func retryTranscript(_ transcript: VoiceTranscript) {
        Task { @MainActor in
            do {
                _ = try await controller.retryVoiceTranscript(id: transcript.id)
                reloadTranscripts()
            } catch {
                CopyHUD.show("Retry failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func moveSelection(delta: Int) {
        let previousIndex = transcriptAnchorID.flatMap { voiceTranscriptIDs.firstIndex(of: $0) } ?? 0
        let state = MainVoiceTranscriptHistoryPresentation.selection(
            afterMovingFrom: transcriptAnchorID,
            orderedIDs: voiceTranscriptIDs,
            delta: delta
        )
        selectedTranscriptIDs = state.selectedIDs
        transcriptAnchorID = state.anchorID

        if PreviewPanel.isVisible,
           let transcriptAnchorID {
            let nextIndex = voiceTranscriptIDs.firstIndex(of: transcriptAnchorID) ?? previousIndex
            previewTranscript(
                id: transcriptAnchorID,
                direction: PreviewPanelTransitionDirection.horizontal(from: previousIndex, to: nextIndex)
            )
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let raw = keyPress.key.character

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "a" {
            selectedTranscriptIDs = Set(voiceTranscriptIDs)
            transcriptAnchorID = voiceTranscriptIDs.first
            return .handled
        }

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "c" {
            copyTranscripts(ids: effectiveTranscriptIDs())
            return .handled
        }

        switch raw {
        case " ":
            previewTranscript(id: effectiveTranscriptIDs().first)
            return .handled
        case "\r":
            copyTranscripts(ids: effectiveTranscriptIDs())
            return .handled
        case Character(UnicodeScalar(NSDownArrowFunctionKey)!):
            moveSelection(delta: 1)
            return .handled
        case Character(UnicodeScalar(NSUpArrowFunctionKey)!):
            moveSelection(delta: -1)
            return .handled
        default:
            return .ignored
        }
    }
}

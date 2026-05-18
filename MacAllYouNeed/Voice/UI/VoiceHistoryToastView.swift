import SwiftUI

struct VoiceHistoryToastView: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MAYNToastContent(message: message, symbol: "trash")
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}

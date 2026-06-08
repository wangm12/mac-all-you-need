import SwiftUI

struct DockCalendarSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MAYNTheme.hover)
                .frame(width: 80, height: 14)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 8) {
                    Circle()
                        .fill(MAYNTheme.hover)
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MAYNTheme.hover)
                        .frame(height: 28)
                }
            }
        }
        .frame(minWidth: 240)
    }
}

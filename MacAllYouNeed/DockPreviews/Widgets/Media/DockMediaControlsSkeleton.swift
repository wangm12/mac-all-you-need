import SwiftUI

struct DockMediaControlsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 100, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 3)
        }
        .frame(minWidth: 280)
        .padding(4)
        .redacted(reason: .placeholder)
    }
}

import SwiftUI

struct SourceAppBadge: View {
    let app: SourceApp?
    let cardBackground: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: cardBackground.opacity(0.0), location: 0.5),
                    .init(color: cardBackground.opacity(0.85), location: 0.85),
                    .init(color: cardBackground, location: 1.0)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .frame(width: 110, height: 80)
            .allowsHitTesting(false)

            if let app, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help(app.displayName)
                    .padding(8)
                    .allowsHitTesting(false)
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }
}

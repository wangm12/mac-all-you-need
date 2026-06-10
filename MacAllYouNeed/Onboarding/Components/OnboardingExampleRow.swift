import SwiftUI

struct OnboardingExample: Identifiable {
    let id = UUID()
    let icon: String
    let input: String
    let output: String
}

/// Input → output example row for feature onboarding pages.
struct OnboardingExampleRow: View {
    let example: OnboardingExample
    var dimmed = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: example.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(example.input)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(example.output)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(dimmed ? 0.72 : 1)
    }
}

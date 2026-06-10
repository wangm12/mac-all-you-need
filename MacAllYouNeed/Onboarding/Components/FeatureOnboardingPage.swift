import SwiftUI

/// Shared layout for per-feature onboarding: what it does → preview → examples → try it.
struct FeatureOnboardingPage<Preview: View, TryIt: View>: View {
    let bullets: [String]
    var previewTitle: String?
    var previewSubtitle: String?
    @ViewBuilder var preview: () -> Preview
    var examplesTitle: String?
    var examples: [OnboardingExample]
    var tryItTitle: String
    var tryItSubtitle: String?
    @ViewBuilder var tryIt: () -> TryIt
    var footnote: String?

    init(
        bullets: [String],
        previewTitle: String? = nil,
        previewSubtitle: String? = nil,
        @ViewBuilder preview: @escaping () -> Preview = { EmptyView() },
        examplesTitle: String? = "Examples",
        examples: [OnboardingExample] = [],
        tryItTitle: String = "Try it",
        tryItSubtitle: String? = nil,
        @ViewBuilder tryIt: @escaping () -> TryIt,
        footnote: String? = nil
    ) {
        self.bullets = bullets
        self.previewTitle = previewTitle
        self.previewSubtitle = previewSubtitle
        self.preview = preview
        self.examplesTitle = examplesTitle
        self.examples = examples
        self.tryItTitle = tryItTitle
        self.tryItSubtitle = tryItSubtitle
        self.tryIt = tryIt
        self.footnote = footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingGroupedSection(
                title: "What it does",
                subtitle: "How this feature fits into your workflow."
            ) {
                OnboardingPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MAYNTheme.success)
                                    .padding(.top, 2)
                                Text(bullet)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if let previewTitle {
                OnboardingGroupedSection(title: previewTitle, subtitle: previewSubtitle) {
                    preview()
                }
            }

            if !examples.isEmpty {
                OnboardingGroupedSection(title: examplesTitle ?? "Examples", subtitle: "What you might say or paste.") {
                    OnboardingPanel {
                        VStack(spacing: 6) {
                            ForEach(examples) { example in
                                OnboardingExampleRow(example: example)
                            }
                        }
                    }
                }
            }

            OnboardingGroupedSection(title: tryItTitle, subtitle: tryItSubtitle) {
                tryIt()
            }

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

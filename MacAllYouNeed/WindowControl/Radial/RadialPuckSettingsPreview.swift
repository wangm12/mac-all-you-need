import SwiftUI
import WebKit

/// Interactive puck HUD demo for Settings and onboarding — loads `window_radial.html`.
struct RadialPuckSettingsPreview: View {
    var body: some View {
        RadialPuckHTMLWebView()
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background {
                LinearGradient(
                    colors: [
                        RadialPuckVisualTokens.settingsPreviewBackgroundTop,
                        RadialPuckVisualTokens.settingsPreviewBackgroundMid,
                        RadialPuckVisualTokens.settingsPreviewBackgroundBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                    .strokeBorder(RadialPuckVisualTokens.settingsPreviewBorder, lineWidth: 1)
            }
            .accessibilityLabel("Radial puck layout demo. Drag from the center puck to aim a layout.")
    }
}

private struct RadialPuckHTMLWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        if let url = Bundle.main.url(forResource: "window_radial", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

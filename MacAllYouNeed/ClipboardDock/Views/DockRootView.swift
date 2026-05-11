import AppKit
import SwiftUI

struct DockRootView: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    let dismiss: () -> Void
    let onPaste: (Int, EventModifiers) -> Void

    /// Height permanently reserved below the tab bar for the multi-select
    /// action bar (44pt bar + 1pt divider). Allocating it always — instead
    /// of growing/shrinking the panel on every selection change — keeps the
    /// carousel cards in a fixed screen-space position and avoids a layout
    /// flicker where the cards momentarily collapse to zero height while
    /// the window resize is in flight.
    private static let actionBarSlotHeight: CGFloat = 45

    var body: some View {
        VStack(spacing: 0) {
            DockTopBar(model: model, dismissDock: dismiss)
            Divider()

            // Action bar is always visible. When nothing is multi-selected
            // its actions fall back to the focused (highlighted) card, so
            // the bar is useful right after the dock opens — no need to
            // click first to make the buttons do something.
            MultiSelectBar(model: model)
                .frame(height: Self.actionBarSlotHeight)

            Group {
                if model.activeList == .snippets {
                    DockSnippetsListView(model: model)
                } else {
                    ClipCarousel(
                        model: model,
                        favicons: favicons,
                        registry: registry,
                        onPaste: onPaste
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Force the outer VStack to fill the NSHostingView's frame. Without
        // this, SwiftUI sizes the VStack to its natural content (just the
        // top bar) regardless of how tall the host's frame is, and the
        // Group's maxHeight: .infinity inside cannot expand into space the
        // outer VStack didn't claim.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(model)
        // No outer `.animation(value: model.selection.isEmpty)` — that
        // modifier propagates implicit animation to every descendant that
        // re-renders on the same diff, which made the per-card selection
        // border fade in over ~180ms after each click. The MultiSelectBar's
        // appearance is animated locally via `transition`-aware
        // `withAnimation` calls in the selection mutators (clearSelection /
        // selectOnly etc.) only when it actually changes appearance state.
        .background(
            // Fully opaque panel surface. `windowBackgroundColor` was still
            // letting the desktop/terminal bleed through faintly (it carries
            // a vibrancy alpha on macOS). `controlBackgroundColor` is the
            // explicit "card/panel" surface and is solid.
            Color(nsColor: .controlBackgroundColor)
        )
        .clipShape(RoundedCorners(radius: 12, corners: [.topLeft, .topRight]))
        .overlay {
            if model.showTransformMenu {
                TransformMenu(model: model, isPresented: $model.showTransformMenu)
            }
        }
        .overlay {
            if model.isQuickLooking {
                QuickLookOverlay(model: model)
                    .animation(.easeOut(duration: 0.15), value: model.isQuickLooking)
            }
        }
        .overlay {
            if model.showCheatsheet {
                CheatsheetOverlay(registry: registry)
                    .animation(.easeOut(duration: 0.15), value: model.showCheatsheet)
            }
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: NSRectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tr),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bl),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tl, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        return path
    }
}

private struct NSRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = NSRectCorner(rawValue: 1 << 0)
    static let topRight = NSRectCorner(rawValue: 1 << 1)
    static let bottomLeft = NSRectCorner(rawValue: 1 << 2)
    static let bottomRight = NSRectCorner(rawValue: 1 << 3)
}

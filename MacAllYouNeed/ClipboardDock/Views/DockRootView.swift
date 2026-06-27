import AppKit
import Core
import SwiftUI

struct DockRootView: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    let dismiss: () -> Void
    let onPaste: (Int, EventModifiers) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var snippetEditorMode: DockSnippetEditorMode?

    private static let shellCornerRadius = MAYNControlMetrics.hudRadius

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
                    DockSnippetsListView(model: model, editorMode: $snippetEditorMode)
                } else {
                    ClipCarousel(
                        model: model,
                        favicons: favicons,
                        registry: registry,
                        onPaste: onPaste
                    )
                }
            }
            // Same opaque panel color as DockTopBar + MultiSelectBar so the
            // carousel/snippets area reads as one solid surface. The outer
            // shell uses Liquid Glass on macOS 26; without this fill the
            // desktop bleeds through between cards.
            .background(Color(nsColor: .controlBackgroundColor))
            .id(model.activeList.animationID)
            .transition(contentTransition)
            .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: model.activeList.animationID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Force the outer VStack to fill the NSHostingView's frame. Without
        // this, SwiftUI sizes the VStack to its natural content (just the
        // top bar) regardless of how tall the host's frame is, and the
        // Group's maxHeight: .infinity inside cannot expand into space the
        // outer VStack didn't claim.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(model)
        .background { dockShellBackdrop }
        .clipShape(dockShellShape)
        .overlay {
            dockShellShape.stroke(MAYNTheme.hairline, lineWidth: 1)
        }
        .overlay {
            if model.showTransformMenu {
                TransformMenu(model: model, isPresented: $model.showTransformMenu)
            }
        }
        .overlay {
            if model.isQuickLooking {
                QuickLookOverlay(model: model)
                    .animation(MAYNMotion.animation(.toastIn, reduceMotion: reduceMotion), value: model.isQuickLooking)
            }
        }
        .overlay {
            if model.showCheatsheet {
                CheatsheetOverlay(registry: registry)
                    .animation(MAYNMotion.animation(.toastIn, reduceMotion: reduceMotion), value: model.showCheatsheet)
            }
        }
        .overlay {
            snippetEditorOverlay
                .animation(MAYNMotion.animation(.toastIn, reduceMotion: reduceMotion), value: snippetEditorMode?.id)
        }
        .onChange(of: model.activeList.animationID) { _, _ in
            if model.activeList != .snippets {
                dismissSnippetEditor()
            }
        }
    }

    private var dockShellShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.shellCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Self.shellCornerRadius,
            style: .continuous
        )
    }

    @ViewBuilder
    private var dockShellBackdrop: some View {
        let shape = dockShellShape
        if reduceTransparency {
            shape.fill(MAYNTheme.contentPanelElevated(colorScheme))
        } else if #available(macOS 26.0, *) {
            shape.fill(Color.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(MAYNMaterial.overlay.material)
        }
    }

    private var contentTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var snippetEditorOverlay: some View {
        if let mode = snippetEditorMode {
            ZStack {
                Color.black.opacity(SnippetEditorPresentation.scrimOpacity)
                    .contentShape(Rectangle())
                    .onTapGesture {}

                snippetEditor(for: mode)
                    .background(
                        MAYNTheme.panel,
                        in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                            .stroke(MAYNTheme.strongBorder, lineWidth: 1)
                    )
                    .shadow(
                        color: Color.black.opacity(SnippetEditorPresentation.shadowOpacity),
                        radius: SnippetEditorPresentation.shadowRadius,
                        y: SnippetEditorPresentation.shadowY
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private func snippetEditor(for mode: DockSnippetEditorMode) -> some View {
        switch mode {
        case .new:
            SnippetSheet(
                editing: nil,
                existingSnippets: model.snippetItems,
                isPresented: snippetEditorPresentedBinding,
                onSave: { name, body, trigger in
                    try await model.createSnippet(name: name, body: body, trigger: trigger)
                }
            )

        case let .draft(draft):
            SnippetSheet(
                editing: nil,
                draft: draft,
                existingSnippets: model.snippetItems,
                isPresented: snippetEditorPresentedBinding,
                onSave: { name, body, trigger in
                    try await model.createSnippet(name: name, body: body, trigger: trigger)
                }
            )

        case let .edit(id):
            SnippetSheet(
                editing: model.snippetItems.first(where: { $0.id == id }),
                existingSnippets: model.snippetItems,
                isPresented: snippetEditorPresentedBinding,
                onSave: { name, body, trigger in
                    try await model.updateSnippet(id: id, name: name, body: body, trigger: trigger)
                }
            )
        }
    }

    private var snippetEditorPresentedBinding: Binding<Bool> {
        Binding(
            get: { snippetEditorMode != nil },
            set: { visible in
                if !visible {
                    dismissSnippetEditor()
                }
            }
        )
    }

    private func dismissSnippetEditor() {
        snippetEditorMode = nil
        model.clearPendingSnippetDraft()
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

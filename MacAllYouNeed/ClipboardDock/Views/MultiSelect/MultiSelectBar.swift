import AppKit
import Platform
import SwiftUI

struct MultiSelectBar: View {
    @Bindable var model: ClipboardDockModel

    var body: some View {
        HStack(spacing: 12) {
            countLabel
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()

            // Copy puts the card(s) on the system clipboard. Dock stays
            // open; user dismisses + ⌘V into target app themselves.
            Button("Copy") {
                Task { await model.copyEffectiveTargets(plainText: false) }
            }
            .disabled(targetCount == 0)

            // Copy plain forces text-only (strips HTML/RTF formatting),
            // useful when pasting into rich-text apps that would otherwise
            // inherit the source styling.
            Button("Copy plain") {
                Task { await model.copyEffectiveTargets(plainText: true) }
            }
            .disabled(targetCount == 0)

            // One unified Pin menu — picks any pinboard. Each entry shows
            // the same colored dot as the corresponding tab in the top bar
            // so the menu is visually consistent with the tab list the user
            // is choosing from.
            Menu("Pin to list") {
                if model.availableLists.isEmpty {
                    Text("No lists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.availableLists, id: \.id) { board in
                        Button {
                            Task {
                                await model.addToPinboard(
                                    itemIDs: model.effectiveActionTargets,
                                    boardID: board.id
                                )
                                model.clearSelection()
                            }
                        } label: {
                            // SwiftUI Menu turns the label into an
                            // NSMenuItem; SF Symbols come through as
                            // template images and lose their color. We
                            // rasterize a non-template NSImage with the
                            // color baked in so the dot reads as the actual
                            // pinboard color, not flat grey.
                            Label {
                                Text(board.name)
                            } icon: {
                                Image(nsImage: Self.dotNSImage(forHex: board.color))
                            }
                        }
                    }
                }
            }
            .disabled(targetCount == 0)

            Menu("Transform") {
                ForEach(TextTransform.allCases, id: \.self) { transform in
                    Button(label(for: transform)) {
                        Task {
                            await model.applyTransform(transform, saveAsNew: true)
                        }
                    }
                }
            }
            .disabled(targetCount == 0)

            Button("Delete", role: .destructive) {
                Task { await model.deleteEffectiveTargets() }
            }
            .disabled(targetCount == 0)

            // Only meaningful when there's an actual multi-select to clear;
            // hide otherwise so the bar isn't cluttered when it's just
            // operating on the focused card.
            if !model.selection.isEmpty {
                Button {
                    model.clearSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        // Same opaque panel color as DockRootView + DockTopBar so the
        // three strips read as one continuous surface. Materials let the
        // backdrop (terminals, browsers) bleed through.
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// "N selected" when explicitly multi-selected; otherwise "Focused card"
    /// to make clear the bar is acting on the highlighted item by default.
    /// "No items" when the dock is empty.
    @ViewBuilder
    private var countLabel: some View {
        if !model.selection.isEmpty {
            Text("\(model.selection.count) selected")
        } else if model.items.indices.contains(model.focusedIndex) {
            Text("Focused card")
        } else {
            Text("No items")
        }
    }

    private var targetCount: Int { model.effectiveActionTargets.count }

    /// Hex → SwiftUI Color, mirroring `DockListTabs.colorFromHex`. Static so
    /// the menu's Label closure doesn't capture self.
    static func color(forHex hex: String?) -> Color? {
        guard let hex else { return nil }
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Render a colored circle into a fresh, non-template NSImage. SwiftUI
    /// Menu items become NSMenuItem on macOS and treat SF Symbol images as
    /// templates — strip the color, render flat grey. Providing our own
    /// non-template NSImage with the swatch baked in is the only reliable
    /// way to surface the pinboard color in the menu.
    static func dotNSImage(forHex hex: String?) -> NSImage {
        let nsColor: NSColor = {
            guard let hex else { return .secondaryLabelColor }
            let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard normalized.count == 6,
                  let value = UInt64(normalized, radix: 16)
            else { return .secondaryLabelColor }
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }()
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func label(for transform: TextTransform) -> String {
        switch transform {
        case .lowercase: return "Lowercase"
        case .uppercase: return "Uppercase"
        case .titleCase: return "Title Case"
        case .trim: return "Trim"
        case .stripHTML: return "Strip HTML"
        case .prettyJSON: return "Pretty JSON"
        case .minifyJSON: return "Minify JSON"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .sortLines: return "Sort Lines"
        case .dedupeLines: return "Dedupe Lines"
        }
    }
}

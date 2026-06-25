import Core
import SwiftUI

enum RadialLayoutGlyphKind {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
    case full

    init(action: WindowAction) {
        switch action {
        case .leftHalf: self = .left
        case .rightHalf: self = .right
        case .topHalf: self = .top
        case .bottomHalf: self = .bottom
        case .topLeft: self = .topLeft
        case .topRight: self = .topRight
        case .bottomLeft: self = .bottomLeft
        case .bottomRight: self = .bottomRight
        case .maximize: self = .full
        default: self = .full
        }
    }
}

/// Mini window icon drawn on the active puck.
struct RadialLayoutGlyph: View {
    let kind: RadialLayoutGlyphKind
    var scale: CGFloat = 1
    var opacity: CGFloat = 1

    private let frameWidth: CGFloat = 18
    private let frameHeight: CGFloat = 12
    private let corner: CGFloat = 2.5
    private let inset: CGFloat = 2.1

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var transform = CGAffineTransform(translationX: center.x, y: center.y)
            transform = transform.scaledBy(x: scale, y: scale)
            context.concatenate(transform)

            let outer = CGRect(
                x: -frameWidth / 2,
                y: -frameHeight / 2,
                width: frameWidth,
                height: frameHeight
            )
            var strokePath = Path(roundedRect: outer, cornerRadius: corner)
            context.stroke(strokePath, with: .color(RadialPuckVisualTokens.glyphStroke.opacity(opacity)), lineWidth: 1.25)

            let fillRect = filledRegion(in: outer)
            var fillPath = Path(roundedRect: fillRect, cornerRadius: 1.3)
            context.fill(fillPath, with: .color(RadialPuckVisualTokens.glyphFill.opacity(opacity)))
        }
        .frame(width: 28, height: 22)
        .allowsHitTesting(false)
    }

    private func filledRegion(in outer: CGRect) -> CGRect {
        var fx = outer.minX + inset
        var fy = outer.minY + inset
        var fw = outer.width - inset * 2
        var fh = outer.height - inset * 2
        switch kind {
        case .left: fw /= 2
        case .right: fx += fw / 2; fw /= 2
        case .top: fh /= 2
        case .bottom: fy += fh / 2; fh /= 2
        case .topLeft: fw /= 2; fh /= 2
        case .topRight: fx += fw / 2; fw /= 2; fh /= 2
        case .bottomLeft: fw /= 2; fy += fh / 2; fh /= 2
        case .bottomRight: fx += fw / 2; fw /= 2; fy += fh / 2; fh /= 2
        case .full: break
        }
        return CGRect(x: fx, y: fy, width: fw, height: fh)
    }
}

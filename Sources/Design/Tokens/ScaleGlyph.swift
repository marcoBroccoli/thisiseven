import SwiftUI

/// Balance-scale mark — path matches `docs/even-design-system` SVG
/// (`viewBox="0 0 16 16"`: beam, fulcrum triangle, base).
///
/// Draw-on: trim this single shape `0…1` for one continuous stroke
/// (beam → triangle → base), matching the restored splash behavior.
public struct EvenScaleGlyph: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        // Beam — <line x1="1.5" y1="6.8" x2="14.5" y2="4.6">
        p.move(to: CGPoint(x: 1.5 * s, y: 6.8 * s))
        p.addLine(to: CGPoint(x: 14.5 * s, y: 4.6 * s))
        // Fulcrum — <path d="M8 6.4 L10.6 10.6 H5.4 Z">
        p.move(to: CGPoint(x: 8 * s, y: 6.4 * s))
        p.addLine(to: CGPoint(x: 10.6 * s, y: 10.6 * s))
        p.addLine(to: CGPoint(x: 5.4 * s, y: 10.6 * s))
        p.closeSubpath()
        // Base — <line x1="4.5" y1="13.4" x2="11.5" y2="13.4">
        p.move(to: CGPoint(x: 4.5 * s, y: 13.4 * s))
        p.addLine(to: CGPoint(x: 11.5 * s, y: 13.4 * s))
        return p
    }
}

public extension EvenScaleGlyph {
    /// Design SVG: `stroke-width="1.4"` in `viewBox="0 0 16 16"`.
    /// Scales with the mark — e.g. ~7pt at the 80pt splash, ~5pt at 58pt welcome.
    static func lineWidth(forSide side: CGFloat) -> CGFloat {
        1.4 * (side / 16)
    }
}

#Preview("EvenScaleGlyph") {
    EvenScaleGlyph()
        .stroke(
            EvenTokens.espresso,
            style: StrokeStyle(
                lineWidth: EvenScaleGlyph.lineWidth(forSide: 80),
                lineCap: .round,
                lineJoin: .round
            )
        )
        .frame(width: 80, height: 80)
        .padding()
        .evenPaperBackground()
}

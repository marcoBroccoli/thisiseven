import SwiftUI

/// Balance-scale mark used on splash / welcome.
public struct EvenScaleGlyph: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        var p = Path()
        p.move(to: CGPoint(x: 1.5 * s, y: 6.8 * s))
        p.addLine(to: CGPoint(x: 14.5 * s, y: 4.6 * s))
        p.move(to: CGPoint(x: 8 * s, y: 6.4 * s))
        p.addLine(to: CGPoint(x: 10.6 * s, y: 10.6 * s))
        p.addLine(to: CGPoint(x: 5.4 * s, y: 10.6 * s))
        p.closeSubpath()
        p.move(to: CGPoint(x: 4.5 * s, y: 13.4 * s))
        p.addLine(to: CGPoint(x: 11.5 * s, y: 13.4 * s))
        return p
    }
}

#Preview("EvenScaleGlyph") {
    EvenScaleGlyph()
        .stroke(EvenTokens.espresso, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 80, height: 80)
        .padding()
        .background(EvenTokens.paperRaised)
}

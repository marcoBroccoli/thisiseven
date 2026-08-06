import SwiftUI

/// Compact “Even” wordmark — scale glyph + italic serif (toolbar / screen headers).
public struct EvenBrandMark: View {
    public var side: CGFloat
    public var fontSize: CGFloat
    public var showsTrailingSpacer: Bool

    public init(
        side: CGFloat = 15,
        fontSize: CGFloat = 18,
        showsTrailingSpacer: Bool = false
    ) {
        self.side = side
        self.fontSize = fontSize
        self.showsTrailingSpacer = showsTrailingSpacer
    }

    public var body: some View {
        HStack(spacing: 7) {
            EvenScaleGlyph()
                .stroke(
                    EvenTokens.espresso,
                    style: StrokeStyle(
                        lineWidth: EvenScaleGlyph.lineWidth(forSide: side),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: side, height: side)
            Text("Even")
                .font(.system(size: fontSize, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
            if showsTrailingSpacer {
                Spacer()
            }
        }
        .fixedSize(horizontal: !showsTrailingSpacer, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Even")
    }
}

#Preview("EvenBrandMark") {
    EvenBrandMark()
        .padding()
        .evenPaperBackground()
}

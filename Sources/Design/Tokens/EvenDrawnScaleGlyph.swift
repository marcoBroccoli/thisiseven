import SwiftUI

/// Draws the design-system scale glyph as **one continuous stroke**
/// (`EvenScaleGlyph` trimmed 0…1: beam → fulcrum → base).
public struct EvenDrawnScaleGlyph: View {
    public var progress: CGFloat
    public var side: CGFloat
    public var color: Color

    public init(
        progress: CGFloat,
        side: CGFloat = 80,
        color: Color = EvenTokens.espresso
    ) {
        self.progress = min(1, max(0, progress))
        self.side = side
        self.color = color
    }

    public var body: some View {
        EvenScaleGlyph()
            .trim(from: 0, to: progress)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: EvenScaleGlyph.lineWidth(forSide: side),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: side, height: side)
    }
}

/// Splash composition: single-stroke drawn glyph + fading wordmark.
public struct EvenSplashMark: View {
    public var glyphSize: CGFloat
    public var wordmarkSize: CGFloat
    public var autoplay: Bool
    public var onFinished: (() -> Void)?

    @State private var drawProgress: CGFloat = 0
    @State private var showWordmark = false

    public init(
        glyphSize: CGFloat = 80,
        wordmarkSize: CGFloat = 40,
        autoplay: Bool = true,
        onFinished: (() -> Void)? = nil
    ) {
        self.glyphSize = glyphSize
        self.wordmarkSize = wordmarkSize
        self.autoplay = autoplay
        self.onFinished = onFinished
    }

    /// Total autoplay time until glyph is drawn and wordmark is on screen.
    /// Glyph ease-in-out 0.65s; wordmark spring delay 0.45s + ~0.5s settle.
    public static let autoplayDuration: Duration = .milliseconds(1200)

    public var body: some View {
        VStack(spacing: 0) {
            EvenDrawnScaleGlyph(progress: drawProgress, side: glyphSize)

            Text("Even")
                .font(.system(size: wordmarkSize, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
                .tracking(-0.4)
                .padding(.top, 16)
                .opacity(showWordmark ? 1 : 0)
                .offset(y: showWordmark ? 0 : 8)
        }
        .onAppear { playIfNeeded() }
    }

    private func playIfNeeded() {
        guard autoplay else {
            drawProgress = 1
            showWordmark = true
            onFinished?()
            return
        }
        drawProgress = 0
        showWordmark = false
        // Same timing as the restored single-stroke splash (git `34be01d`).
        withAnimation(.easeInOut(duration: 0.65)) {
            drawProgress = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45)) {
            showWordmark = true
        }
        Task {
            try? await Task.sleep(for: Self.autoplayDuration)
            onFinished?()
        }
    }
}

#Preview("Drawn glyph · mid") {
    EvenDrawnScaleGlyph(progress: 0.55, side: 80)
        .padding(40)
        .evenPaperBackground()
}

#Preview("Drawn glyph · full") {
    EvenDrawnScaleGlyph(progress: 1, side: 80)
        .padding(40)
        .evenPaperBackground()
}

#Preview("Splash mark") {
    EvenSplashMark()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .evenPaperBackground()
}

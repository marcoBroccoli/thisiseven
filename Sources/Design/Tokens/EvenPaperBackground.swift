import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tiled noise matching design-system `data-grain`.
    ///
    /// Specks are translucent **black** so the overlay composites with normal
    /// alpha blending — `.multiply` above the whole app forced the compositor
    /// off its fast path on every scrolled frame. Rendered at `scale = 1` and
    /// upsampled so specks blur softly instead of landing as hard 3px blocks.
    private let evenGrainTile: UIImage = {
        let side = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        var rng = SystemRandomNumberGenerator()
        return renderer.image { ctx in
            for y in 0 ..< side {
                for x in 0 ..< side where Double.random(in: 0 ... 1, using: &rng) < 0.14 {
                    let alpha = CGFloat.random(in: 0.25 ... 0.9, using: &rng)
                    ctx.cgContext.setFillColor(UIColor(white: 0, alpha: alpha).cgColor)
                    ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
#endif

/// Subtle paper-grain overlay — pointer-events none, normal alpha blend
/// (darkening is baked into the tile's black specks).
public struct EvenGrainOverlay: View {
    public var opacity: Double

    public init(opacity: Double = 0.04) {
        self.opacity = opacity
    }

    public var body: some View {
        #if canImport(UIKit)
            Image(uiImage: evenGrainTile)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        #else
            Color.clear.allowsHitTesting(false)
        #endif
    }
}

/// Cream paper + grain — default screen ground from the design system.
public struct EvenPaperBackground: View {
    public var color: Color

    public init(color: Color = EvenTokens.paperRaised) {
        self.color = color
    }

    public var body: some View {
        ZStack {
            color
            EvenGrainOverlay()
        }
        .ignoresSafeArea()
    }
}

public extension View {
    /// Fills behind the view with paper + grain (safe-area ignored).
    func evenPaperBackground(_ color: Color = EvenTokens.paperRaised) -> some View {
        background { EvenPaperBackground(color: color) }
    }

    /// Draws grain on top of the view. Prefer baking grain into
    /// ``EvenPaperBackground`` / ``evenPaperBackground`` behind content —
    /// a root overlay on opaque cards reads as see-through under normal blend.
    func evenGrainOverlay(opacity: Double = 0.04) -> some View {
        overlay { EvenGrainOverlay(opacity: opacity) }
    }
}

#Preview("Paper + grain") {
    Text("Even")
        .font(.system(size: 40, weight: .semibold, design: .serif))
        .italic()
        .foregroundStyle(EvenTokens.espresso)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .evenPaperBackground()
}

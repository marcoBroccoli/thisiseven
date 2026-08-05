import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tiled noise matching design-system `data-grain` (≈5.5% multiply).
    private let evenGrainTile: UIImage = {
        let side = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        var rng = SystemRandomNumberGenerator()
        return renderer.image { ctx in
            for y in 0 ..< side {
                for x in 0 ..< side where Bool.random(using: &rng) {
                    let gray = CGFloat.random(in: 0 ... 1, using: &rng)
                    ctx.cgContext.setFillColor(UIColor(white: gray, alpha: 1).cgColor)
                    ctx.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
#endif

/// Subtle paper-grain overlay — pointer-events none, multiply blend.
public struct EvenGrainOverlay: View {
    public var opacity: Double

    public init(opacity: Double = 0.055) {
        self.opacity = opacity
    }

    public var body: some View {
        #if canImport(UIKit)
            Image(uiImage: evenGrainTile)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.multiply)
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

    /// Draws grain on top of the view (multiply). Use at the app root so every
    /// screen — including TabView — shares one paper texture.
    func evenGrainOverlay(opacity: Double = 0.055) -> some View {
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

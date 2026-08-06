import SwiftUI

/// Soft settle / fade-up motion from the design system (`fadeUp` ≈ 8pt).
public enum EvenMotion {
    public static let settle = Animation.easeOut(duration: 0.32)
    public static let step = Animation.easeInOut(duration: 0.38)
    public static let page = Animation.easeInOut(duration: 0.34)
    public static let reveal = Animation.easeOut(duration: 0.28)
    public static let indicator = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Top-edge toast enter / exit (slide from top, settle, return up).
    public static let toast = Animation.spring(response: 0.42, dampingFraction: 0.88)
    /// Toast stretching out of the Dynamic Island — loose, liquid, unhurried,
    /// with just enough underdamping to overshoot exactly once as it lands.
    public static let toastEmerge = Animation.spring(response: 0.72, dampingFraction: 0.74)
    /// Toast being sucked back into the Island — no overshoot, fully seated.
    public static let toastRetract = Animation.spring(response: 0.6, dampingFraction: 1)

    /// A CTA swapping state in place — label text, or icon ⇄ spinner.
    public static let ctaSwap = Animation.easeInOut(duration: 0.26)

    public static let fadeUpOffset: CGFloat = 8

    /// Defocus cross-fade for swapped glyphs. A plain opacity fade between two
    /// different shapes reads as a flicker; blurring through the swap makes it
    /// resolve instead.
    public static var blurFade: EvenBlurFade {
        EvenBlurFade()
    }

    /// Opacity + slight rise — design `fadeUp`.
    public static var fadeUp: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: fadeUpOffset)),
            removal: .opacity.combined(with: .offset(y: -fadeUpOffset * 0.5))
        )
    }

    public static var fadeOnly: AnyTransition {
        .opacity
    }
}

public struct EvenBlurFade: Transition {
    public var radius: CGFloat
    public var scale: CGFloat

    public init(radius: CGFloat = 5, scale: CGFloat = 0.84) {
        self.radius = radius
        self.scale = scale
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : radius)
            .scaleEffect(phase.isIdentity ? 1 : scale)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

public extension View {
    /// Staggered settle-in for gated chrome (tagline, CTA, footer…).
    func evenSettleIn(visible: Bool, delay: Double = 0) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : EvenMotion.fadeUpOffset)
            .animation(EvenMotion.settle.delay(delay), value: visible)
    }
}

private struct EvenMotionFadeUpPreview: View {
    @State private var on = false
    var body: some View {
        VStack(spacing: 16) {
            if on {
                Text("Settles in")
                    .font(.system(size: 22, design: .serif))
                    .italic()
                    .transition(EvenMotion.fadeUp)
            }
            Button(on ? "Hide" : "Reveal") {
                withAnimation(EvenMotion.reveal) { on.toggle() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .evenPaperBackground()
    }
}

#Preview("EvenMotion · fadeUp") {
    EvenMotionFadeUpPreview()
}

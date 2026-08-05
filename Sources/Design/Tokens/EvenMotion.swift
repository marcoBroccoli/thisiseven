import SwiftUI

/// Soft settle / fade-up motion from the design system (`fadeUp` ≈ 8pt).
public enum EvenMotion {
    public static let settle = Animation.easeOut(duration: 0.32)
    public static let step = Animation.easeInOut(duration: 0.38)
    public static let page = Animation.easeInOut(duration: 0.34)
    public static let reveal = Animation.easeOut(duration: 0.28)
    public static let indicator = Animation.spring(response: 0.38, dampingFraction: 0.86)

    public static let fadeUpOffset: CGFloat = 8

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

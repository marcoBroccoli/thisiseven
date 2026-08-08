#if os(iOS)
    import Design
    import SwiftUI
    import UIKit

    /// Hold-to-pour. A tap is too cheap for the one action that ends a week, so
    /// the control fills under the thumb and only tips at the end. Letting go
    /// early relaxes it back — nothing happens by accident.
    struct ResetHoldToPour: View {
        /// Fired once, when the hold reaches the end.
        let completed: () -> Void
        var title: String = "Hold to pour"
        var enabled: Bool = true

        static let duration: Double = 1.5

        @State private var progress: CGFloat = 0
        @State private var isPressing = false
        @State private var didComplete = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                // A bare tint on paper reads as a disabled button; the stroke
                // says "this is a control, it just isn't filled yet".
                Capsule()
                    .fill(EvenTokens.espresso.opacity(0.08))
                    .overlay(
                        Capsule().strokeBorder(EvenTokens.espresso.opacity(0.45), lineWidth: 1.2)
                    )

                // The pour itself: espresso rising from the leading edge.
                GeometryReader { geo in
                    Capsule()
                        .fill(EvenTokens.espresso)
                        .frame(width: max(0, geo.size.width * progress))
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(progress > 0.55 ? EvenTokens.paperRaised : EvenTokens.espresso)
                    .animation(EvenMotion.ctaSwap, value: progress > 0.55)
            }
            .frame(height: 52)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .scaleEffect(isPressing && !reduceMotion ? 0.985 : 1)
            .animation(EvenMotion.reveal, value: isPressing)
            .allowsHitTesting(enabled)
            .opacity(enabled ? 1 : 0.55)
            .onLongPressGesture(
                minimumDuration: Self.duration,
                maximumDistance: 60,
                perform: finish,
                onPressingChanged: pressingChanged
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityHint("Hold to close the week and level the beam")
            .accessibilityIdentifier("reset-hold-to-pour")
            // VoiceOver users get a plain activation — a timed hold is not a
            // reasonable thing to ask of a rotor gesture.
            .accessibilityAction { finish() }
        }

        private func pressingChanged(_ pressing: Bool) {
            isPressing = pressing
            if pressing {
                didComplete = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.linear(duration: Self.duration)) { progress = 1 }
            } else if !didComplete {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { progress = 0 }
            }
        }

        private func finish() {
            guard !didComplete else { return }
            didComplete = true
            progress = 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completed()
        }
    }

    #Preview("Hold to pour") {
        ResetHoldToPour(completed: {})
            .padding(28)
            .evenPaperBackground()
    }
#endif

// Copied from freeflex-ios
// `Packages/Design/Sources/ComponentsSwiftUI/Others/ViewModifiers/ShimmerModifier.swift`
// (Temper). Source left intact in FreeFlex — this is a copy, not a move.

import SwiftUI

/// A view modifier that applies an animated "shimmer" to any view, typically to show that
/// an operation is in progress.
public struct ShimmerModifier: ViewModifier {
    let animation: Animation
    // If the reduced motion setting is enabled, the animation will be nil
    @Environment(\.accessibilityReduceMotion) var reducedMotion
    @State private var phase: CGFloat = 0

    /// Initializes his modifier with a custom animation,
    /// - Parameter animation: A custom animation. The default animation is
    ///   `.linear(duration: 1.5).repeatForever(autoreverses: false)`.
    public init(animation: Animation = Self.defaultAnimation) {
        self.animation = animation
    }

    /// The default animation effect.
    public static let defaultAnimation = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

    public func body(content: Content) -> some View {
        ZStack {
            content
                .modifier(
                    AnimatedMask(phase: phase)
                )
                .onAppear {
                    withAnimation(animation) {
                        phase = 1
                    }
                }
        }
    }

    /// An animatable modifier to interpolate between `phase` values.
    /// `@preconcurrency` — Swift 6: `Animatable` requirements are nonisolated.
    struct AnimatedMask: ViewModifier, @preconcurrency Animatable {
        var phase: CGFloat = 0

        var animatableData: CGFloat {
            get { phase }
            set { phase = newValue }
        }

        func body(content: Content) -> some View {
            content
                .mask(GradientMask(phase: phase).scaleEffect(3))
        }
    }

    /// Animatable gradient to use as mask.
    /// The `phase` parameter shifts the gradient, moving the opaque band.
    struct GradientMask: View {
        let phase: CGFloat
        let centerColor = Color.black
        let edgeColor = Color.black.opacity(0.6)
        @Environment(\.layoutDirection) private var layoutDirection

        var body: some View {
            let isRightToLeft = layoutDirection == .rightToLeft
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: edgeColor, location: phase),
                    .init(color: centerColor, location: phase + 0.1),
                    .init(color: edgeColor, location: phase + 0.2),
                ]),
                startPoint: isRightToLeft ? .bottomTrailing : .topLeading,
                endPoint: isRightToLeft ? .topLeading : .bottomTrailing
            )
        }
    }
}

public extension View {
    /// Adds an animated shimmering effect to any view, typically to show that
    /// an operation is in progress.
    /// - Parameters:
    ///   - active: Convenience parameter to conditionally enable the effect. Defaults to `true`.
    ///   - animation: A custom animation. The default animation is
    ///   `.linear(duration: 1.5).repeatForever(autoreverses: false)`.
    @ViewBuilder func shimmering(
        active: Bool = true,
        animation: Animation = ShimmerModifier.defaultAnimation
    ) -> some View {
        if active {
            modifier(ShimmerModifier(animation: animation))
        } else {
            self
        }
    }
}

#if DEBUG
    #Preview("Shimmer") {
        VStack {
            Text("SwiftUI Shimmer")
                .shimmering()
            Text("SwiftUI Shimmer")
                .preferredColorScheme(.light)
                .shimmering()
            Text("SwiftUI Shimmer")
                .preferredColorScheme(.dark)
                .shimmering()
            Text(String(repeating: "Shimmer", count: 12))
                .shimmering()
        }
        .padding()
    }
#endif

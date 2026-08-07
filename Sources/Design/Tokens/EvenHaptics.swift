#if os(iOS)
    import SwiftUI
    import UIKit

    /// Visual parity with `.plain` — adds a light impact haptic on press.
    public struct EvenHapticButtonStyle: ButtonStyle {
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, isPressed in
                    guard isPressed else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        }
    }

    public extension ButtonStyle where Self == EvenHapticButtonStyle {
        static var evenPlain: EvenHapticButtonStyle { EvenHapticButtonStyle() }
    }
#endif

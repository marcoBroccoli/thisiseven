import Design
import SwiftUI

/// Shared layout tokens + typography for Connections setup path screens.
enum ConnectionsSetupChrome {
    static let horizontalInset: CGFloat = 28
    static let topInset: CGFloat = 12
    static let bottomInset: CGFloat = 40
    static let inkMuted = Color(hex: 0x6E6353)

    static func heroBlock(
        eyebrow: String? = nil,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(EvenTokens.stone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(title)
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, eyebrow == nil ? 0 : 10)

            italicNote(subtitle, size: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
    }

    static func italicNote(
        _ text: String,
        size: CGFloat,
        color: Color = EvenTokens.stone
    ) -> some View {
        Text(text)
            .font(.system(size: size, design: .serif))
            .italic()
            .foregroundStyle(color)
    }

    /// Step body only — the shell owns the bottom CTA via `safeAreaInset`.
    ///
    /// Multi-child `@ViewBuilder` content must sit in a `VStack` before any
    /// `.frame(alignment:)` — applying the frame to the bare tuple overlays
    /// every child at the same origin.
    static func stepScreen<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

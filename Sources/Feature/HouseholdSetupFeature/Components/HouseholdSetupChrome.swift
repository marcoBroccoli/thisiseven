#if os(iOS)
    import Design
    import SwiftUI

    /// Shared layout tokens + typography used by household setup path screens.
    enum HouseholdSetupChrome {
        static let horizontalInset: CGFloat = 28
        static let topInset: CGFloat = 12
        static let bottomInset: CGFloat = 40
        static let inkMuted = Color(hex: 0x6E6353)

        enum Tile {
            static let width: CGFloat = 44
            static let height: CGFloat = 58
            static let spacing: CGFloat = 8
        }

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

        static func stepScreen<Content: View>(
            @ViewBuilder content: () -> Content
        ) -> some View {
            stepScreen(content: content, footer: { EmptyView() })
        }

        static func stepScreen<Content: View, Footer: View>(
            @ViewBuilder content: () -> Content,
            @ViewBuilder footer: () -> Footer
        ) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                content()
                Spacer(minLength: 0)
                footer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
#endif

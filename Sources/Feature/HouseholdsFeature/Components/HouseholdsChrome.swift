#if os(iOS)
    import Design
    import SwiftUI

    /// Shared layout + typography for the households screens. One place for the
    /// page gutter, the card radius and the eyebrow — no scattered numbers.
    enum HouseholdsChrome {
        static let pageHorizontal: CGFloat = 20
        static let sectionGap: CGFloat = 26
        static let cardRadius: CGFloat = 14
        static let cardPadding: CGFloat = 16

        static func eyebrow(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(EvenTokens.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        static func fieldLabel(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(EvenTokens.stone)
        }

        static func note(_ text: String, size: CGFloat = 13) -> some View {
            Text(text)
                .font(.system(size: size, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.stone)
                // Notes wrap; a card row would otherwise clip them to one line.
                .fixedSize(horizontal: false, vertical: true)
        }

        static func heroBlock(
            eyebrow: String? = nil,
            title: String,
            subtitle: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                if let eyebrow {
                    Self.eyebrow(eyebrow)
                }
                Text(title)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, eyebrow == nil ? 0 : 10)
                note(subtitle, size: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }

    extension View {
        /// Paper card with the household-page stroke. `accented` marks the one
        /// the app is currently looking at.
        func householdsCardChrome(accented: Bool = false) -> some View {
            background(EvenTokens.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: HouseholdsChrome.cardRadius, style: .continuous)
                        .stroke(
                            accented ? EvenTokens.terracotta.opacity(0.75) : EvenTokens.espresso.opacity(0.16),
                            lineWidth: accented ? 2 : 1.5
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: HouseholdsChrome.cardRadius, style: .continuous))
        }
    }
#endif

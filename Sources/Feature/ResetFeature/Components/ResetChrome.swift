#if os(iOS)
    import Design
    import SwiftUI

    /// Shared typography + layout for the five beats, so each step body only
    /// carries its own content.
    enum ResetChrome {
        static let horizontalInset: CGFloat = 28
        static let topInset: CGFloat = 12
        static let bottomInset: CGFloat = 24
        static let beatSpacing: CGFloat = 20

        /// Small tracked label above a beat ("WEEK 12 · THE SPLIT").
        static func eyebrow(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.6)
                .foregroundStyle(EvenTokens.stone)
        }

        /// Serif headline — the ritual's voice.
        static func title(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }

        static func body(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(EvenTokens.espresso.opacity(0.7))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where we are in the ritual — a row of thin rules, not dots. Quiet enough
    /// to sit above a beam without competing with it.
    struct ResetProgressRail: View {
        let count: Int
        let index: Int

        var body: some View {
            HStack(spacing: 6) {
                ForEach(0 ..< count, id: \.self) { position in
                    Capsule()
                        .fill(
                            position <= index
                                ? EvenTokens.espresso.opacity(0.55)
                                : EvenTokens.espresso.opacity(0.13)
                        )
                        .frame(height: 2)
                }
            }
            .animation(EvenMotion.step, value: index)
            .accessibilityElement()
            .accessibilityLabel("Step \(index + 1) of \(count)")
        }
    }

    /// One split row: label, the two shares, and an owner-tinted bar. Same clay
    /// and pine as the beam pans so the eye carries the mapping across beats.
    struct ResetSplitRow: View {
        let label: String
        let mePct: Int
        let partnerPct: Int
        let meName: String
        let partnerName: String
        let hasPartner: Bool
        /// Drives the fill-in; the shell flips it as the beat settles.
        let filled: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Spacer(minLength: 12)
                    Text("\(mePct)")
                        .foregroundStyle(EvenTokens.terracotta)
                        + Text(hasPartner ? " · \(partnerPct)" : "")
                        .foregroundStyle(EvenTokens.pine)
                }
                .font(.system(size: 16, weight: .medium, design: .serif))

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Capsule()
                            .fill(EvenTokens.terracotta)
                            .frame(width: width(mePct, in: geo.size.width))
                        if hasPartner {
                            Capsule()
                                .fill(EvenTokens.pine)
                                .frame(width: width(partnerPct, in: geo.size.width))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 6)
                }
                .frame(height: 6)
                .background(
                    Capsule().fill(EvenTokens.espresso.opacity(0.07)).frame(height: 6)
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                hasPartner
                    ? "\(label): \(meName) \(mePct) percent, \(partnerName) \(partnerPct) percent"
                    : "\(label): \(meName) \(mePct) percent"
            )
        }

        private func width(_ pct: Int, in total: CGFloat) -> CGFloat {
            guard filled, total > 0 else { return 0 }
            let usable = total - 2
            return max(0, usable * CGFloat(pct) / 100)
        }
    }

    /// The partner's kind thing before I have written mine — legible as *there*,
    /// not as readable. A blur alone reads as a loading state, so the veil keeps
    /// the paper card and adds a small line of why.
    struct ResetVeiledNote: View {
        let partnerName: String

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Two lines of something kind, waiting.")
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
                    .blur(radius: 6)
                    .accessibilityHidden(true)
                HStack(spacing: 7) {
                    Image(systemName: "lock")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(partnerName.uppercased()) WROTE ONE. YOURS FIRST.")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.6)
                }
                .foregroundStyle(EvenTokens.stone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EvenTokens.paperCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(EvenTokens.espresso.opacity(0.1), style: StrokeStyle(
                        lineWidth: 1, dash: [4, 4]
                    ))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(partnerName) wrote one. Write yours to read it.")
        }
    }

    /// The partner's kind thing, revealed.
    struct ResetRevealedNote: View {
        let partnerName: String
        let body_: String

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(body_)
                    .font(.system(size: 17, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("— \(partnerName.uppercased())")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EvenTokens.paperCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(EvenTokens.pine.opacity(0.28), lineWidth: 1)
            )
        }
    }

    /// A trade waiting on me — one line, one accept.
    struct ResetTradeRow: View {
        let title: String
        let busy: Bool
        let accept: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HANDED OVER")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(EvenTokens.stone)
                    Text(title)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                }
                Spacer(minLength: 8)
                Button(action: accept) {
                    Text(busy ? "…" : "Take it")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(EvenTokens.paperRaised)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(EvenTokens.espresso))
                }
                .buttonStyle(.evenPlain)
                .allowsHitTesting(!busy)
                .accessibilityIdentifier("reset-accept-trade")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(EvenTokens.paperCard)
            )
        }
    }
#endif

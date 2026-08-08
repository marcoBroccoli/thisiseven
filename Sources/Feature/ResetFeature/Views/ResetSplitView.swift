#if os(iOS)
    import Design
    import EvenCore
    import SwiftUI

    /// Beat 2 — the split. Three rows, drawn in one after another so the week
    /// reads as a sequence rather than a table dumped on screen.
    struct ResetSplitView: View {
        let weekIndex: Int
        let rows: [ResetRow]
        let me: Member?
        let partner: Member?

        @State private var shown = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: ResetChrome.beatSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    ResetChrome.eyebrow("WEEK \(weekIndex) · THE SPLIT")
                    ResetChrome.title("Here's how it fell.")
                }

                Spacer(minLength: 0)

                VStack(spacing: 22) {
                    ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                        ResetSplitRow(
                            label: row.label,
                            mePct: row.mePct,
                            partnerPct: row.partnerPct,
                            meName: me?.displayName ?? "You",
                            partnerName: partner?.displayName ?? "Them",
                            hasPartner: partner != nil,
                            filled: index < shown
                        )
                        .opacity(index < shown ? 1 : 0)
                        .offset(y: index < shown ? 0 : EvenMotion.fadeUpOffset)
                    }
                }
                .padding(.top, 4)

                legend
                    .opacity(shown >= rows.count ? 1 : 0)
                    .animation(EvenMotion.reveal, value: shown)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .task { await drawIn() }
        }

        @ViewBuilder
        private var legend: some View {
            if partner != nil {
                HStack(spacing: 14) {
                    swatch(EvenTokens.terracotta, me?.displayName ?? "You")
                    swatch(EvenTokens.pine, partner?.displayName ?? "Them")
                }
            }
        }

        private func swatch(_ color: Color, _ name: String) -> some View {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(EvenTokens.stone)
            }
        }

        /// Reduce Motion still gets the rows — all at once, no bar sweep.
        private func drawIn() async {
            guard !reduceMotion else {
                shown = rows.count
                return
            }
            for step in 1 ... max(rows.count, 1) {
                try? await Task.sleep(for: .milliseconds(step == 1 ? 160 : 240))
                withAnimation(EvenMotion.settle) { shown = step }
            }
        }
    }
#endif

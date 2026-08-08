#if os(iOS)
    import Design
    import SwiftUI

    /// Beat 3 — the biggest carry. One sentence, nothing else on the page. This
    /// is the beat the whole ritual exists for; anything added here dilutes it.
    struct ResetCarryView: View {
        let sentence: String

        @State private var shown = false

        var body: some View {
            VStack(alignment: .leading, spacing: 26) {
                Spacer(minLength: 0)

                ResetChrome.eyebrow("THE BIGGEST CARRY")
                    .evenSettleIn(visible: shown)

                Text(sentence)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .evenSettleIn(visible: shown, delay: 0.22)

                Rectangle()
                    .fill(EvenTokens.terracotta)
                    .frame(width: shown ? 46 : 0, height: 2)
                    .animation(EvenMotion.step.delay(0.55), value: shown)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onAppear { shown = true }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("The biggest carry. \(sentence)")
        }
    }
#endif

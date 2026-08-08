#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI

    /// Beat 1 — the week, finished. The beam the household has been looking at
    /// all week, at its final tilt, settling in one last time.
    struct ResetCoverView: View {
        let weekIndex: Int
        let summary: Summary?
        let me: Member?
        let partner: Member?
        let caption: String?

        @State private var settled = false

        var body: some View {
            VStack(alignment: .leading, spacing: ResetChrome.beatSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    ResetChrome.eyebrow("SUNDAY")
                    ResetChrome.title("Week \(weekIndex) is complete.")
                }
                .evenSettleIn(visible: settled)

                beam
                    .frame(height: 236)
                    .opacity(settled ? 1 : 0)
                    .animation(EvenMotion.settle.delay(0.18), value: settled)

                if let caption {
                    ResetChrome.body(caption)
                        .evenSettleIn(visible: settled, delay: 0.34)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onAppear { settled = true }
        }

        private var beam: some View {
            EvenBeamScale(
                configuration: ResetBeam.configuration(
                    weekIndex: weekIndex, summary: summary, me: me, partner: partner
                )
            )
        }
    }
#endif

#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI

    /// Beat 5 — the pour. Hold, and the pans empty: the pebbles leave, the beam
    /// comes back to level, and the next week starts owing nobody anything.
    @ViewAction(for: ResetReducer.self)
    struct ResetPourView: View {
        @Bindable var store: StoreOf<ResetReducer>

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    ResetChrome.eyebrow(headerEyebrow)
                    ResetChrome.title(headline)
                        .animation(EvenMotion.step, value: store.pour)
                }

                ZStack {
                    EvenBeamScale(configuration: beamConfiguration)
                    if !reduceMotion {
                        ResetPourFall(active: store.pouredOut)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 236)

                if let message = store.pour.message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(EvenTokens.terracotta)
                        .transition(EvenMotion.fadeUp)
                }

                if store.pour == .waiting || store.pour.isFailed {
                    ResetChrome.body(
                        store.hasPartner
                            ? "Nothing carries over. Whatever you each owed the other is settled by the week ending."
                            : "Nothing carries over. Next week starts clean."
                    )
                    .transition(EvenMotion.fadeUp)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(EvenMotion.step, value: store.pouredOut)
        }

        private var headerEyebrow: String {
            store.pour == .poured ? "LEVEL" : "THE POUR"
        }

        private var headline: String {
            switch store.pour {
            case .poured: "Week \(store.weekIndex + 1) begins level."
            case .pouring: "Pouring it out…"
            default: "Ready to pour week \(store.weekIndex) out?"
            }
        }

        /// While pouring (and after) the pans are empty and the beam sits at
        /// 50/50 — the beam primitive animates the balls out and the tilt back.
        private var beamConfiguration: EvenBeamScaleConfiguration {
            ResetBeam.configuration(
                weekIndex: store.pour == .poured ? store.weekIndex + 1 : store.weekIndex,
                summary: store.summary,
                me: store.me,
                partner: store.partner,
                emptied: store.pouredOut
            )
        }
    }

    /// The pebbles leaving. The beam primitive fades its own balls out; this adds
    /// the fall underneath so the emptying reads as a pour rather than a delete.
    struct ResetPourFall: View {
        let active: Bool

        private struct Drop: Identifiable {
            let id: Int
            let x: CGFloat
            let size: CGFloat
            let delay: Double
            let clay: Bool
        }

        private static let drops: [Drop] = (0 ..< 12).map { index in
            let clay = index.isMultiple(of: 2)
            return Drop(
                id: index,
                // Clustered under each pan, not scattered across the page.
                x: (clay ? 0.24 : 0.76) + CGFloat(index % 3) * 0.035 - 0.035,
                size: [5, 6.5, 8][index % 3],
                delay: Double(index) * 0.055,
                clay: clay
            )
        }

        @State private var fallen = false

        var body: some View {
            GeometryReader { geo in
                ForEach(Self.drops) { drop in
                    Circle()
                        .fill(drop.clay ? EvenTokens.terracotta : EvenTokens.pine)
                        .frame(width: drop.size, height: drop.size)
                        .position(
                            x: geo.size.width * drop.x,
                            y: fallen ? geo.size.height + 24 : geo.size.height * 0.46
                        )
                        .opacity(fallen ? 0 : (active ? 0.9 : 0))
                        .animation(
                            .easeIn(duration: 0.62).delay(drop.delay),
                            value: fallen
                        )
                }
            }
            .onChange(of: active) { _, isActive in
                guard isActive else { return }
                fallen = false
                // One frame at rest so the drops exist before they fall.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fallen = true }
            }
        }
    }
#endif

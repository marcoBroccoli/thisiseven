#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI

    /// Beat 4 — one kind thing. An exchange, not a broadcast: my partner's note
    /// stays veiled until I have handed mine over. Solo households never see
    /// this beat — the shell drops it from `beats`.
    @ViewAction(for: ResetReducer.self)
    struct ResetKindView: View {
        @Bindable var store: StoreOf<ResetReducer>

        @FocusState private var writing: Bool

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: ResetChrome.beatSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        ResetChrome.eyebrow("ONE KIND THING")
                        ResetChrome.title("Name one thing they did.")
                        ResetChrome.body(
                            "Small counts. It goes to \(partnerName) when you're both done."
                        )
                    }

                    composer
                    partnerNote

                    if !trades.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ResetChrome.eyebrow("ON THE TABLE FOR NEXT WEEK")
                            ForEach(trades) { trade in
                                ResetTradeRow(
                                    title: trade.taskTitle,
                                    busy: store.busyTrade == trade.id
                                ) {
                                    send(.acceptTrade(trade.id))
                                }
                            }
                        }
                        .padding(.top, 4)
                        .transition(EvenMotion.fadeUp)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .animation(EvenMotion.reveal, value: store.partnerAppreciationRevealed)
            .animation(EvenMotion.reveal, value: trades.count)
        }

        private var partnerName: String {
            store.partner?.displayName ?? "them"
        }

        private var trades: [Trade] {
            store.myPendingTrades
        }

        private var composer: some View {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $store.appreciationDraft)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                    .scrollContentBackground(.hidden)
                    .frame(height: 96)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(EvenTokens.paperCard)
                    )
                    .overlay(alignment: .topLeading) {
                        if store.appreciationDraft.isEmpty {
                            Text("You handled the whole Thursday without me asking.")
                                .font(.system(size: 16, design: .serif))
                                .italic()
                                .foregroundStyle(EvenTokens.stone.opacity(0.65))
                                .padding(.horizontal, 17)
                                .padding(.top, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                store.appreciationSaved
                                    ? EvenTokens.pine.opacity(0.35)
                                    : EvenTokens.espresso.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                    .focused($writing)
                    .accessibilityIdentifier("reset-appreciation-field")

                HStack(spacing: 12) {
                    Button {
                        writing = false
                        send(.saveAppreciationTapped, animation: EvenMotion.reveal)
                    } label: {
                        Text(saveTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                store.appreciationSaved
                                    ? EvenTokens.pine : EvenTokens.paperRaised
                            )
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(
                                Capsule().fill(
                                    store.appreciationSaved
                                        ? EvenTokens.pine.opacity(0.12)
                                        : (store.canSaveAppreciation
                                            ? EvenTokens.espresso : EvenTokens.stone)
                                )
                            )
                    }
                    .buttonStyle(.evenPlain)
                    .allowsHitTesting(store.canSaveAppreciation)
                    .accessibilityIdentifier("reset-save-appreciation")
                    Spacer(minLength: 0)
                }
            }
        }

        private var saveTitle: String {
            if store.isSavingAppreciation { return "Sending…" }
            return store.appreciationSaved ? "Sent \u{2713}" : "Send it"
        }

        @ViewBuilder
        private var partnerNote: some View {
            if let note = store.partnerAppreciation, let body = note.body, !body.isEmpty {
                if store.partnerAppreciationRevealed {
                    ResetRevealedNote(partnerName: partnerName, body_: body)
                        .transition(EvenMotion.blurFade)
                } else {
                    ResetVeiledNote(partnerName: partnerName)
                        .transition(EvenMotion.blurFade)
                }
            } else {
                Text("\(partnerName.uppercased()) HASN'T WRITTEN THEIRS YET.")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
            }
        }
    }
#endif

#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI

    /// The Sunday ritual shell — paper, a progress rail, one beat at a time, and
    /// a footer that only ever holds one primary control.
    ///
    /// Advance by tap (right half) or swipe; back by tap (left half) or swipe.
    /// The pour beat is the exception: it advances only through the hold.
    @ViewAction(for: ResetReducer.self)
    public struct ResetView: View {
        @Bindable public var store: StoreOf<ResetReducer>

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(store: StoreOf<ResetReducer>) {
            self.store = store
        }

        public var body: some View {
            content
                // Grain belongs *behind* the content (Design doctrine) — a root
                // grain overlay reads as see-through over the cards.
                .evenPaperBackground(EvenTokens.paperGround)
                .onAppear { send(.appear) }
                .interactiveDismissDisabled(store.pour == .pouring)
        }

        private var content: some View {
            VStack(alignment: .leading, spacing: 18) {
                header

                beatBody
                    .id(store.beat)
                    .transition(reduceMotion ? EvenMotion.fadeOnly : EvenMotion.fadeUp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay { tapZones }
                    // The kind beat owns a text field — a container drag gesture
                    // there swallows taps meant for the editor.
                    .gesture(swipe, isEnabled: store.beat != .kind)
                    .animation(EvenMotion.page, value: store.beat)
            }
            .padding(.horizontal, ResetChrome.horizontalInset)
            .padding(.top, ResetChrome.topInset)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }

        // MARK: Chrome

        private var header: some View {
            VStack(spacing: 12) {
                ResetProgressRail(count: store.beats.count, index: store.beatIndex)
                HStack {
                    EvenBrandMark()
                    Spacer()
                    if store.pour != .poured {
                        Button { send(.dismissTapped) } label: {
                            Text("Later today")
                                .font(.system(size: 13))
                                .foregroundStyle(EvenTokens.stone)
                        }
                        .buttonStyle(.evenPlain)
                        .accessibilityIdentifier("reset-later")
                        .transition(EvenMotion.fadeOnly)
                    }
                }
                .animation(EvenMotion.reveal, value: store.pour)
            }
            .padding(.top, 6)
        }

        @ViewBuilder
        private var beatBody: some View {
            if store.isLoading {
                loading
            } else if let message = store.loadError, store.reset == nil {
                failure(message)
            } else {
                switch store.beat {
                case .cover:
                    ResetCoverView(
                        weekIndex: store.weekIndex,
                        summary: store.summary,
                        me: store.me,
                        partner: store.partner,
                        caption: store.summary?.caption
                    )
                case .split:
                    ResetSplitView(
                        weekIndex: store.weekIndex,
                        rows: store.reset?.rows ?? [],
                        me: store.me,
                        partner: store.partner
                    )
                case .carry:
                    ResetCarryView(sentence: store.reset?.biggestCarry ?? "")
                case .kind:
                    ResetKindView(store: store)
                case .pour:
                    ResetPourView(store: store)
                }
            }
        }

        private var loading: some View {
            VStack(alignment: .leading, spacing: 14) {
                ResetChrome.eyebrow("SUNDAY")
                ResetChrome.title("Adding up the week…")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        private func failure(_ message: String) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                ResetChrome.eyebrow("SUNDAY")
                ResetChrome.title("Couldn't add up the week.")
                ResetChrome.body(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        // MARK: Footer

        @ViewBuilder
        private var footer: some View {
            Group {
                switch store.pour {
                case .poured where store.beat == .pour:
                    EvenPrimaryButton("Start week \(store.weekIndex + 1)", accessibilityId: "reset-finish") {
                        send(.finishTapped)
                    }
                case .pouring where store.beat == .pour:
                    ResetHoldToPour(completed: {}, title: "Pouring…", enabled: false)
                default:
                    if store.beat == .pour {
                        ResetHoldToPour(
                            completed: { send(.holdCompleted, animation: EvenMotion.step) },
                            title: store.pour.isFailed ? "Hold to try again" : "Hold to pour",
                            enabled: !store.isLoading
                        )
                    } else {
                        EvenPrimaryButton(
                            "Continue",
                            enabled: !store.isLoading,
                            accessibilityId: "reset-continue"
                        ) {
                            send(.advance, animation: EvenMotion.page)
                        }
                    }
                }
            }
            .padding(.horizontal, ResetChrome.horizontalInset)
            .padding(.bottom, ResetChrome.bottomInset)
            .animation(EvenMotion.step, value: store.pour)
            .animation(EvenMotion.step, value: store.beat)
        }

        // MARK: Advancing

        /// Left third goes back, the rest goes forward — story-card convention.
        /// The kind beat opts out: it holds a text field, and a stray tap there
        /// must not skip a page.
        @ViewBuilder
        private var tapZones: some View {
            if store.beat != .kind, store.beat != .pour, !store.isLoading {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { send(.back, animation: EvenMotion.page) }
                            .frame(width: geo.size.width / 3)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { send(.advance, animation: EvenMotion.page) }
                    }
                }
                .accessibilityHidden(true)
            }
        }

        private var swipe: some Gesture {
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard store.pour != .pouring, store.pour != .poured else { return }
                    if value.translation.width < -40 {
                        send(.advance, animation: EvenMotion.page)
                    } else if value.translation.width > 40 {
                        send(.back, animation: EvenMotion.page)
                    }
                }
        }
    }

    #Preview("Reset · the pour") {
        ResetView(store: ResetPreviewSupport.ritual())
    }

    #Preview("Reset · solo household") {
        ResetView(store: ResetPreviewSupport.solo())
    }
#endif

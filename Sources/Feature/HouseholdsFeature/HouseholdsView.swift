#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI
    import UIKit

    /// Your places — switch between them, hand out the free seat, answer the
    /// invites addressed to you. Pushed from Profile.
    @ViewAction(for: HouseholdsReducer.self)
    public struct HouseholdsView: View {
        @Bindable public var store: StoreOf<HouseholdsReducer>

        public init(store: StoreOf<HouseholdsReducer>) {
            self.store = store
        }

        public var body: some View {
            pageBody
                // Path animation stays on the body — animating the inset too
                // would cross-fade the CTA instead of morphing it.
                .animation(EvenMotion.page, value: store.path)
                .safeAreaInset(edge: .bottom) { footer }
                .toolbar { toolbarContent }
                .navigationBarBackButtonHidden(store.showsBack)
                .evenPaperNavigationChrome()
                .alert(
                    leaveTitle,
                    isPresented: Binding(
                        get: { store.leavingHousehold != nil },
                        set: { if !$0 { send(.cancelLeave) } }
                    )
                ) {
                    Button("Cancel", role: .cancel) { send(.cancelLeave) }
                    Button("Leave", role: .destructive) {
                        send(.confirmLeave, animation: EvenMotion.reveal)
                    }
                } message: {
                    Text(store.leaveConfirmationMessage)
                }
                .onAppear { send(.appear) }
        }

        private var pageBody: some View {
            ScrollView {
                Group {
                    switch store.path {
                    case .list:
                        HouseholdsListView(store: store)
                    case .create:
                        HouseholdCreateFormView(store: store)
                    case .accept:
                        HouseholdAcceptInviteView(store: store)
                    case .join:
                        HouseholdJoinFormView(store: store)
                    }
                }
                .padding(.horizontal, HouseholdsChrome.pageHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(store.path)
                .transition(EvenMotion.fadeUp)
            }
            .evenScrollOnPaper()
            .refreshable { await send(.refresh).finish() }
        }

        /// One persistent CTA for every step — the title and the target change,
        /// the button does not. The list adds the second way in underneath;
        /// when it leaves, the primary rides down to the edge.
        private var footer: some View {
            VStack(spacing: 10) {
                EvenPrimaryButton(
                    footerTitle,
                    enabled: footerEnabled,
                    accessibilityId: "households-primary"
                ) {
                    send(footerAction, animation: EvenMotion.page)
                }

                if store.path == .list {
                    Button {
                        send(.joinTapped, animation: EvenMotion.page)
                    } label: {
                        Text("Join with a code")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .underline(true, color: EvenTokens.stone)
                            .foregroundStyle(EvenTokens.stone)
                            .padding(6)
                    }
                    .buttonStyle(.evenPlain)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("households-join-with-code")
                    .transition(EvenMotion.fadeUp)
                }
            }
            .animation(EvenMotion.page, value: store.path == .list)
            .padding(.horizontal, HouseholdsChrome.pageHorizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }

        private var footerTitle: String {
            switch store.path {
            case .list: return store.households.isEmpty ? "Start a household" : "Start another household"
            case .create: return store.working ? "Starting…" : "Create household"
            case .accept: return store.working ? "Taking the seat…" : "Take the seat"
            case .join: return store.working ? "Joining…" : "Join household"
            }
        }

        private var footerEnabled: Bool {
            switch store.path {
            case .list: return !store.isLoading
            case .create: return store.canSubmitCreate
            case .accept: return store.canSubmitAccept
            case .join: return store.canSubmitJoin
            }
        }

        private var footerAction: HouseholdsReducer.Action.View {
            switch store.path {
            case .list: return .createTapped
            case .create: return .submitCreate
            case .accept: return .submitAccept
            case .join: return .submitJoin
            }
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            if store.showsBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        send(.backTapped, animation: EvenMotion.page)
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("households-back")
                }
            }
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
            }
        }

        private var leaveTitle: String {
            guard let name = store.leavingHousehold?.name else { return "Leave household?" }
            return "Leave \(name)?"
        }

        private var title: String {
            switch store.path {
            case .list: return "Households"
            case .create: return "New household"
            case .accept: return "Take the seat"
            case .join: return "Join a household"
            }
        }
    }

    #Preview("Households · list") {
        NavigationStack {
            HouseholdsView(store: HouseholdsPreviewSupport.populated())
        }
    }

    #Preview("Households · loading") {
        NavigationStack {
            HouseholdsView(store: HouseholdsPreviewSupport.loading())
        }
    }

    #Preview("Households · leaving") {
        NavigationStack {
            HouseholdsView(store: HouseholdsPreviewSupport.leaveConfirmation())
        }
    }

    #Preview("Households · join with a code") {
        NavigationStack {
            HouseholdsView(store: HouseholdsPreviewSupport.joining())
        }
    }

    #Preview("Households · only invites") {
        NavigationStack {
            HouseholdsView(store: HouseholdsPreviewSupport.invitesOnly())
        }
    }
#endif

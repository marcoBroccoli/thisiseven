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
        /// the button does not.
        private var footer: some View {
            EvenPrimaryButton(
                footerTitle,
                enabled: footerEnabled,
                accessibilityId: "households-primary"
            ) {
                send(footerAction, animation: EvenMotion.page)
            }
            .padding(.horizontal, HouseholdsChrome.pageHorizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }

        private var footerTitle: String {
            switch store.path {
            case .list: return store.households.isEmpty ? "Start a household" : "Start another household"
            case .create: return store.working ? "Starting…" : "Create household"
            case .accept: return store.working ? "Taking the seat…" : "Take the seat"
            }
        }

        private var footerEnabled: Bool {
            switch store.path {
            case .list: return !store.isLoading
            case .create: return store.canSubmitCreate
            case .accept: return store.canSubmitAccept
            }
        }

        private var footerAction: HouseholdsReducer.Action.View {
            switch store.path {
            case .list: return .createTapped
            case .create: return .submitCreate
            case .accept: return .submitAccept
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

        private var title: String {
            switch store.path {
            case .list: return "Households"
            case .create: return "New household"
            case .accept: return "Take the seat"
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

    #Preview("Households · only invites") {
        NavigationStack {
            HouseholdsView(store: HouseholdsPreviewSupport.invitesOnly())
        }
    }
#endif

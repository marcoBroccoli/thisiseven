#if os(iOS)
    import ComposableArchitecture
    import Dependencies
    import Design
    import HouseholdClient
    import InboxFeature
    import ProfileFeature
    import ResetFeature
    import SwiftUI
    import TodayFeature

    @ViewAction(for: MainTabReducer.self)
    public struct MainTabView: View {
        @Bindable public var store: StoreOf<MainTabReducer>
        @Dependency(\.householdClient) var householdClient

        public init(store: StoreOf<MainTabReducer>) {
            self.store = store
        }

        public var body: some View {
            TabView(selection: $store.tab.sending(\.view.selectTab)) {
                Tab("Today", systemImage: "house", value: MainTabReducer.State.Tab.today) {
                    TodayView(store: store.scope(state: \.today, action: \.today))
                }

                Tab("Inbox", systemImage: "tray", value: MainTabReducer.State.Tab.inbox) {
                    InboxView(store: store.scope(state: \.inbox, action: \.inbox))
                }
                .badge(inboxBadgeCount)

                Tab("Profile", systemImage: "person.crop.circle", value: MainTabReducer.State.Tab.profile) {
                    ProfileView(store: store.scope(state: \.profile, action: \.profile))
                }
            }
            .tint(EvenTokens.espresso)
            .environment(\.evenAvatarLoader, avatarLoader)
            .task { await send(.appear).finish() }
            // The Sunday ritual owns the whole screen — it is not a card that
            // shares the page with the tabs it interrupts.
            .fullScreenCover(item: $store.scope(state: \.reset, action: \.reset)) { resetStore in
                ResetView(store: resetStore)
            }
        }

        private var avatarLoader: EvenAvatarLoader? {
            { [householdClient] memberId in
                try? await householdClient.fetchAvatar(memberId)
            }
        }

        /// Prefer live Inbox drafts once fetched; otherwise Summary’s pending count
        /// so the badge shows before the Inbox tab is opened.
        private var inboxBadgeCount: Int {
            if store.inbox.hasLoadedDrafts {
                store.inbox.pendingBadgeCount
            } else {
                store.today.summary?.pendingDraftCount ?? 0
            }
        }
    }

    #Preview("Main tabs") {
        MainTabView(store: MainTabPreviewSupport.populated())
    }
#endif

#if os(iOS)
    import ComposableArchitecture
    import Dependencies
    import Design
    import HouseholdClient
    import IGTabBar
    import InboxFeature
    import ProfileFeature
    import SwiftUI
    import TodayFeature

    @ViewAction(for: MainTabReducer.self)
    public struct MainTabView: View {
        @Bindable public var store: StoreOf<MainTabReducer>
        @Dependency(\.householdClient) var householdClient
        @State private var tabBarProgress: CGFloat = 0

        public init(store: StoreOf<MainTabReducer>) {
            self.store = store
        }

        public var body: some View {
            TabView(selection: $store.tab.sending(\.view.selectTab)) {
                TodayView(
                    store: store.scope(state: \.today, action: \.today),
                    tabBarProgress: $tabBarProgress
                )
                .hideNativeTabBar()
                .tag(MainTabReducer.State.Tab.today)

                InboxView(
                    store: store.scope(state: \.inbox, action: \.inbox),
                    tabBarProgress: $tabBarProgress
                )
                .hideNativeTabBar()
                .tag(MainTabReducer.State.Tab.inbox)

                ProfileView(
                    store: store.scope(state: \.profile, action: \.profile),
                    tabBarProgress: $tabBarProgress
                )
                .hideNativeTabBar()
                .tag(MainTabReducer.State.Tab.profile)
            }
            .tint(EvenTokens.espresso)
            .toolbarVisibility(.hidden, for: .tabBar)
            .overlay(alignment: .bottom) {
                IGStyleTabBar(
                    selection: $store.tab.sending(\.view.selectTab),
                    configuration: IGStyleTabBarConfiguration(
                        selectedSegmentTint: EvenTokens.espresso.opacity(0.14),
                        foreground: EvenTokens.espresso,
                        badgeFill: EvenTokens.terracotta,
                        badgeForeground: EvenTokens.paperCard
                    ),
                    onInteraction: expandTabBar
                ) { tab in
                    switch tab {
                    case .today: .symbol("house")
                    case .inbox: .symbol("tray", badge: inboxBadgeCount)
                    case .profile: .symbol("person.crop.circle")
                    }
                }
                .igTabBarChrome(progress: tabBarProgress, collapses: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Main tabs")
            }
            .environment(\.evenAvatarLoader) { [householdClient] memberId in
                try? await householdClient.fetchAvatar(memberId)
            }
            .task { await send(.appear).finish() }
        }

        private func expandTabBar() {
            guard tabBarProgress != 0 else { return }
            withAnimation(.interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)) {
                tabBarProgress = 0
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
        MainTabView(store: Store(initialState: MainTabReducer.State()) { MainTabReducer() })
    }
#endif

#if os(iOS)
    import ComposableArchitecture
    import Design
    import InboxFeature
    import SwiftUI
    import TodayFeature

    @ViewAction(for: MainTabReducer.self)
    public struct MainTabView: View {
        @Bindable public var store: StoreOf<MainTabReducer>

        public init(store: StoreOf<MainTabReducer>) {
            self.store = store
        }

        public var body: some View {
            TabView(selection: $store.tab.sending(\.view.selectTab)) {
                TodayView(store: store.scope(state: \.today, action: \.today))
                    .tabItem { Label("Today", systemImage: "sun.max") }
                    .tag(MainTabReducer.State.Tab.today)

                InboxView(store: store.scope(state: \.inbox, action: \.inbox))
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .tag(MainTabReducer.State.Tab.inbox)
            }
            .tint(EvenTokens.espresso)
            .toolbarBackground(EvenTokens.paperRaised, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }

    #Preview("Main tabs") {
        MainTabView(store: Store(initialState: MainTabReducer.State()) { MainTabReducer() })
    }
#endif

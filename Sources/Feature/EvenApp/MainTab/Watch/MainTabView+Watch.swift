#if os(watchOS)
    import ComposableArchitecture
    import InboxFeature
    import ProfileFeature
    import SwiftUI
    import TodayFeature

    @ViewAction(for: MainTabReducer.self)
    public struct MainTabView: View {
        @Bindable public var store: StoreOf<MainTabReducer>

        public init(store: StoreOf<MainTabReducer>) {
            self.store = store
        }

        public var body: some View {
            TabView {
                TodayView(store: store.scope(state: \.today, action: \.today))
                InboxView(store: store.scope(state: \.inbox, action: \.inbox))
                ProfileView(store: store.scope(state: \.profile, action: \.profile))
            }
            .task { await send(.appear).finish() }
        }
    }
#endif

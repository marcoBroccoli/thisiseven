#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    @ViewAction(for: TodayReducer.self)
    public struct TodayView: View {
        @Bindable public var store: StoreOf<TodayReducer>

        public init(store: StoreOf<TodayReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Today")
        }
    }
#endif

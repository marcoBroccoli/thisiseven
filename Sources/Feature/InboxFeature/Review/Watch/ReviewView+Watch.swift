#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    @ViewAction(for: ReviewReducer.self)
    public struct ReviewView: View {
        @Bindable public var store: StoreOf<ReviewReducer>

        public init(store: StoreOf<ReviewReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Review")
        }
    }
#endif

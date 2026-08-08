#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    /// SPM / shared-type stub — product Watch UI lives in `ios/EvenWatch`.
    @ViewAction(for: HouseholdsReducer.self)
    public struct HouseholdsView: View {
        @Bindable public var store: StoreOf<HouseholdsReducer>

        public init(store: StoreOf<HouseholdsReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Households")
        }
    }
#endif

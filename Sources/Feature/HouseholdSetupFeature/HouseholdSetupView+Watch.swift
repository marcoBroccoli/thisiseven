#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    @ViewAction(for: HouseholdSetupReducer.self)
    public struct HouseholdSetupView: View {
        @Bindable public var store: StoreOf<HouseholdSetupReducer>

        public init(store: StoreOf<HouseholdSetupReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Household")
        }
    }
#endif

#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    /// SPM / shared-type stub — product Watch UI lives in `ios/EvenWatch`.
    @ViewAction(for: ProfileReducer.self)
    public struct ProfileView: View {
        @Bindable public var store: StoreOf<ProfileReducer>

        public init(store: StoreOf<ProfileReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Profile")
        }
    }
#endif

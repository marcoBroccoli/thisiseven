#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    @ViewAction(for: LoginReducer.self)
    public struct LoginView: View {
        @Bindable public var store: StoreOf<LoginReducer>

        public init(store: StoreOf<LoginReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Login")
        }
    }
#endif

#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    @ViewAction(for: ConnectionsReducer.self)
    public struct ConnectionsView: View {
        @Bindable public var store: StoreOf<ConnectionsReducer>

        public init(store: StoreOf<ConnectionsReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Connections")
        }
    }
#endif

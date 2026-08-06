#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    /// SPM / shared-type stub — product Watch UI lives in `ios/EvenWatch` (Core snapshot).
    /// Replace this body when Inbox becomes a real Watch surface.
    @ViewAction(for: InboxReducer.self)
    public struct InboxView: View {
        @Bindable public var store: StoreOf<InboxReducer>

        public init(store: StoreOf<InboxReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Inbox")
        }
    }
#endif

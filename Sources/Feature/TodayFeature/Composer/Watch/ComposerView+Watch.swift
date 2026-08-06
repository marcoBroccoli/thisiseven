#if os(watchOS)
    import ComposableArchitecture
    import EvenCore
    import SwiftUI

    @ViewAction(for: ComposerReducer.self)
    public struct ComposerView: View {
        @Bindable public var store: StoreOf<ComposerReducer>
        let me: Member?
        let partner: Member?

        public init(store: StoreOf<ComposerReducer>, me: Member?, partner: Member?) {
            self.store = store
            self.me = me
            self.partner = partner
        }

        public var body: some View {
            Text("Composer")
        }
    }
#endif

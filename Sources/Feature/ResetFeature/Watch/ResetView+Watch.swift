#if os(watchOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    /// watchOS stub — the Sunday ritual is a phone moment. The Watch only says
    /// where to go for it.
    public struct ResetView: View {
        @Bindable public var store: StoreOf<ResetReducer>

        public init(store: StoreOf<ResetReducer>) {
            self.store = store
        }

        public var body: some View {
            VStack(spacing: 8) {
                Text("Week \(store.weekIndex) is complete.")
                    .font(.system(size: 15, design: .serif))
                    .multilineTextAlignment(.center)
                Text("Pour it out on your phone.")
                    .font(.system(size: 12))
                    .foregroundStyle(EvenTokens.stone)
            }
            .padding()
        }
    }
#endif

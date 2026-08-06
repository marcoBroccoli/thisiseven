#if os(watchOS)
    import SwiftUI

    /// Placeholder — Watch product UI stays in `ios/EvenWatch` (Core snapshot).
    public struct BootSplashView: View {
        public init(hasPersistedSession _: Bool = false) {}

        public var body: some View {
            Text("Even")
        }
    }
#endif

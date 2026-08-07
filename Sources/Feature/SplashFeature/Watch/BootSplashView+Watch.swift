#if os(watchOS)
    import SwiftUI

    /// Placeholder — Watch product UI stays in `ios/EvenWatch` (Core snapshot).
    public struct BootSplashView: View {
        private let onFinished: () -> Void

        public init(
            hasPersistedSession _: Bool = false,
            onFinished: @escaping () -> Void = {}
        ) {
            self.onFinished = onFinished
        }

        public var body: some View {
            Text("Even")
                .onAppear(perform: onFinished)
        }
    }
#endif

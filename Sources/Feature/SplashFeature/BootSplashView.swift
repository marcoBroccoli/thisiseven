#if os(iOS)
    import Design
    import EvenCore
    import SwiftUI

    /// Boot chrome while `AppReducer` runs bootstrap.
    /// - Persisted session → drawn glyph + wordmark; holds until that beat ends.
    /// - Signed out → paper only; `LoginFeature` plays the staged entrance.
    public struct BootSplashView: View {
        private let hasPersistedSession: Bool
        private let onFinished: () -> Void

        public init(
            hasPersistedSession: Bool = KeychainSessionStorage().load() != nil,
            onFinished: @escaping () -> Void = {}
        ) {
            self.hasPersistedSession = hasPersistedSession
            self.onFinished = onFinished
        }

        public var body: some View {
            Group {
                if hasPersistedSession {
                    EvenSplashMark(
                        glyphSize: 80,
                        wordmarkSize: 40,
                        onFinished: onFinished
                    )
                } else {
                    Color.clear
                        .onAppear(perform: onFinished)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    #Preview("Splash · authenticated") {
        BootSplashView(hasPersistedSession: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .evenPaperBackground()
    }

    #Preview("Splash · signed out") {
        BootSplashView(hasPersistedSession: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .evenPaperBackground()
    }
#endif

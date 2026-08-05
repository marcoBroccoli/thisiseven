import Design
import EvenCore
import SwiftUI

/// Boot chrome while `AppReducer` runs bootstrap.
/// - Persisted session → drawn glyph + wordmark.
/// - Signed out → paper only; `LoginFeature` plays the staged entrance.
public struct BootSplashView: View {
    private let hasPersistedSession: Bool

    public init(hasPersistedSession: Bool = KeychainSessionStorage().load() != nil) {
        self.hasPersistedSession = hasPersistedSession
    }

    public var body: some View {
        Group {
            if hasPersistedSession {
                EvenSplashMark(glyphSize: 80, wordmarkSize: 40)
            } else {
                Color.clear
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

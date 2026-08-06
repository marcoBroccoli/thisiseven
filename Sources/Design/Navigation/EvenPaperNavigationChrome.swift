import SwiftUI

/// Shared NavigationStack content chrome: paper surface, inline title mode,
/// clear system bar, espresso tint. Apply on stack *content* (not behind the
/// stack). Toolbar items stay at the call site — this only packs the repetitive
/// chrome modifiers.
public struct EvenPaperNavigationChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .evenPaperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .tint(EvenTokens.espresso)
    }
}

public extension View {
    /// Paper + clear inline nav + espresso tint (Connections / Household /
    /// Onboarding / Inbox shell pack).
    func evenPaperNavigationChrome() -> some View {
        modifier(EvenPaperNavigationChrome())
    }

    /// ScrollViews over paper — hide the system scroll fill so grain shows through.
    func evenScrollOnPaper() -> some View {
        scrollContentBackground(.hidden)
    }
}

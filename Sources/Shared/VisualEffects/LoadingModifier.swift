import SwiftUI

/// Applies / clears redacted + shimmer when `isLoading` changes.
public struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    let animation: Animation

    public init(
        isLoading: Bool,
        animation: Animation = .easeOut(duration: 0.28)
    ) {
        self.isLoading = isLoading
        self.animation = animation
    }

    public func body(content: Content) -> some View {
        content
            .redacted(reason: isLoading ? .placeholder : [])
            .shimmering(active: isLoading)
            .allowsHitTesting(!isLoading)
            .animation(animation, value: isLoading)
    }
}

public extension View {
    /// Standard loading chrome: redacted placeholder + shimmer, toggled by `isLoading`.
    /// Enable/disable animates with `animation` (shimmer band still uses
    /// ``ShimmerModifier/defaultAnimation`` while active).
    ///
    /// Prefer applying this to the real layout filled with mock content — not a
    /// separate spinner — so the skeleton mirrors the loaded state.
    func loading(
        _ isLoading: Bool,
        animation: Animation = .easeOut(duration: 0.28)
    ) -> some View {
        modifier(LoadingModifier(isLoading: isLoading, animation: animation))
    }
}

#if DEBUG
    #Preview("Loading toggle") {
        @Previewable @State var isLoading = true
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Loading", isOn: $isLoading.animation())
            VStack(alignment: .leading) {
                Text("Approval Inbox").font(.title2)
                Text("Drafts, not tasks.")
                Text(String(repeating: "Card row ", count: 4))
            }
            .loading(isLoading)
        }
        .padding()
    }
#endif

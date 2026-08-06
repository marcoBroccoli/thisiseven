import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Window-level screen metrics. `GeometryReader` inside a `NavigationStack`
/// overlay reports 0 insets, so Island detection reads the window directly.
enum ScreenMetrics {
    /// Top safe-area inset of the active window (0 when unavailable).
    @MainActor
    static var topSafeInset: CGFloat {
        #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene =
                scenes.first(where: { $0.activationState == .foregroundActive })
                    ?? scenes.first
            let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
            return window?.safeAreaInsets.top ?? 0
        #else
            return 0
        #endif
    }

    /// Dynamic Island devices report a notably taller top inset than notch devices.
    static let islandSafeAreaThreshold: CGFloat = 59

    @MainActor
    static var hasDynamicIsland: Bool {
        topSafeInset >= islandSafeAreaThreshold
    }
}

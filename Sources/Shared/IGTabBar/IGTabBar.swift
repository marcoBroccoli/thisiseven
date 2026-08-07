/// Portable Instagram-style floating segmented tab bar — brand-free (no Even tokens).
/// Destined for a shared components package; keep it that way.
///
/// iOS: ``IGStyleTabBar`` + ``View/hideNativeTabBar()`` + ``View/adoptForIGTabBar(_:)``.
/// watchOS: module name only (UIKit control is unavailable).
public enum IGTabBarModule {
    public static let name = "IGTabBar"
}

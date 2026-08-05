import Foundation

/// Process-wide session used by `*ClientLive` for shared API + auth.
/// Features must not import this for domain reads — go through clients instead.
@MainActor
public enum SharedSession {
    public static let store = SessionStore()
}

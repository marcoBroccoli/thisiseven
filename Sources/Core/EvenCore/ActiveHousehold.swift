import Foundation

/// The household the client is currently looking at.
///
/// One person may sit in several households (`docs/product/API.md` → Active
/// household on `/v1/*`). The id is kept in `UserDefaults` under a single key so
/// three readers agree without passing it around:
///
/// - `EvenAPIClient` — sends `X-Household-Id` on every `/v1` request.
/// - `HouseholdRealtimeClient` — the WS upgrade cannot set headers, so it
///   appends `?household_id=`.
/// - Features — via `@Shared(.appStorage(ActiveHousehold.storageKey))`.
///
/// Unset (the fresh-install / build-12 case) means *send nothing*: the server
/// then falls back to the caller's most recently joined household.
public enum ActiveHousehold {
    /// Same key the `@Shared(.appStorage(…))` Feature state binds to.
    public static let storageKey = "evenActiveHouseholdID"

    /// Lowercased uuid string, or `nil` when the client has never picked one.
    /// An empty string is "unset" — `@Shared(.appStorage:)` writes "" to clear.
    public static var id: String? {
        get {
            let raw = defaults.string(forKey: storageKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let uuid = UUID(uuidString: raw) else { return nil }
            return uuid.uuidString.lowercased()
        }
        set {
            guard let newValue, let uuid = UUID(uuidString: newValue) else {
                defaults.set("", forKey: storageKey)
                return
            }
            defaults.set(uuid.uuidString.lowercased(), forKey: storageKey)
        }
    }

    public static func set(_ id: UUID?) {
        self.id = id?.uuidString
    }

    public static func clear() {
        defaults.set("", forKey: storageKey)
    }

    private static var defaults: UserDefaults { .standard }
}

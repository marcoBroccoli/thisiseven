import Foundation

public enum DraftSnoozeService {
    public static func isCurrentlySnoozed(
        _ draft: InboxDraft,
        now: Date = Date()
    ) -> Bool {
        guard let snoozedUntil = draft.snoozedUntil else { return false }
        return snoozedUntil > now
    }
}

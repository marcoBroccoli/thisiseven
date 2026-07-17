import Foundation

public enum CalendarConflictResolver {
    public static func acceptCalendarVersion(for draft: InboxDraft) -> InboxDraft {
        guard let remote = draft.calendarExternalSnapshot else {
            return draft
        }

        var accepted = draft
        accepted.title = remote.title
        accepted.dueDate = remote.dueDate
        accepted.googleEventURL = remote.url ?? draft.googleEventURL
        accepted.status = .approved
        accepted.lastError = nil
        accepted.calendarLastSyncedSnapshot = remote
        accepted.calendarExternalSnapshot = nil
        return accepted
    }

    public static func keepAppVersion(for draft: InboxDraft) -> InboxDraft {
        var kept = draft
        kept.status = .calendarUpdateRequired
        kept.lastError = nil
        kept.calendarExternalSnapshot = nil
        return kept
    }

    public static func changeSummary(local: CalendarEventSnapshot?, remote: CalendarEventSnapshot) -> String {
        guard let local else {
            return "Google Calendar event was modified externally."
        }

        var changes: [String] = []
        if local.title != remote.title {
            changes.append("Title changed from \(local.title) to \(remote.title).")
        }
        if local.dueDate != remote.dueDate {
            changes.append("Due date changed from \(format(local.dueDate)) to \(format(remote.dueDate)).")
        }
        if (local.notes ?? "") != (remote.notes ?? "") {
            changes.append("Notes changed in Google Calendar.")
        }

        return changes.isEmpty ? "Google Calendar event was modified externally." : changes.joined(separator: " ")
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

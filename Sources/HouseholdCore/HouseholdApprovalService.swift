import Foundation

public final class HouseholdApprovalService: Sendable {
    private let calendar: CalendarClient
    private let appBaseURL: URL

    public init(calendar: CalendarClient, appBaseURL: URL) {
        self.calendar = calendar
        self.appBaseURL = appBaseURL
    }

    public func approve(
        _ draft: InboxDraft,
        in household: HouseholdContext,
        reminderMinutesBefore: [Int] = [1_440, 60]
    ) async -> InboxDraft {
        guard let calendarID = household.sharedCalendarID else {
            return retryDraft(draft, message: CalendarClientError.missingCalendarConnection.localizedDescription)
        }

        guard let dueDate = draft.dueDate else {
            return retryDraft(draft, message: CalendarClientError.missingDueDate.localizedDescription)
        }

        var approved = draft
        let event = calendarEvent(
            for: draft,
            calendarID: calendarID,
            dueDate: dueDate,
            household: household,
            reminderMinutesBefore: reminderMinutesBefore
        )

        do {
            let reference = try await calendar.createEvent(event)
            approved.status = .approved
            approved.googleEventID = reference.id
            approved.googleEventURL = reference.url
            approved.lastError = nil
            approved.calendarLastSyncedSnapshot = snapshot(from: event, reference: reference)
            approved.calendarExternalSnapshot = nil
            return approved
        } catch {
            return retryDraft(draft, message: approvalErrorMessage(from: error))
        }
    }

    public func syncExistingCalendarEvent(
        _ draft: InboxDraft,
        in household: HouseholdContext,
        reminderMinutesBefore: [Int] = [1_440, 60]
    ) async -> InboxDraft {
        guard let eventID = draft.googleEventID else {
            return await approve(draft, in: household, reminderMinutesBefore: reminderMinutesBefore)
        }

        guard let calendarID = household.sharedCalendarID else {
            return retryDraft(draft, message: CalendarClientError.missingCalendarConnection.localizedDescription, clearCalendarMapping: false)
        }

        guard let dueDate = draft.dueDate else {
            return retryDraft(draft, message: CalendarClientError.missingDueDate.localizedDescription, clearCalendarMapping: false)
        }

        let event = calendarEvent(
            for: draft,
            calendarID: calendarID,
            dueDate: dueDate,
            household: household,
            reminderMinutesBefore: reminderMinutesBefore
        )

        do {
            let reference = try await calendar.updateEvent(id: eventID, with: event)
            var updated = draft
            updated.status = .approved
            updated.googleEventID = reference.id
            updated.googleEventURL = reference.url ?? draft.googleEventURL
            updated.lastError = nil
            updated.calendarLastSyncedSnapshot = snapshot(from: event, reference: CalendarEventReference(id: reference.id, url: updated.googleEventURL))
            updated.calendarExternalSnapshot = nil
            return updated
        } catch {
            return retryDraft(draft, message: approvalErrorMessage(from: error), clearCalendarMapping: false)
        }
    }

    public func reject(_ draft: InboxDraft, reason: String) -> InboxDraft {
        var rejected = draft
        rejected.status = .rejected
        rejected.lastError = reason
        rejected.googleEventID = nil
        rejected.googleEventURL = nil
        return rejected
    }

    public func reconcileCalendarState(for draft: InboxDraft) async -> InboxDraft {
        guard let eventID = draft.googleEventID else {
            return draft
        }

        do {
            switch try await calendar.eventStatus(for: eventID) {
            case .present:
                return draft
            case .deleted:
                var changed = draft
                changed.status = .changedExternally
                changed.lastError = "Google Calendar event was deleted externally."
                return changed
            case .modifiedExternally:
                var changed = draft
                changed.status = .changedExternally
                if let remoteSnapshot = try await calendar.eventSnapshot(for: eventID) {
                    changed.calendarExternalSnapshot = remoteSnapshot
                    changed.lastError = CalendarConflictResolver.changeSummary(
                        local: draft.calendarLastSyncedSnapshot,
                        remote: remoteSnapshot
                    )
                } else {
                    changed.lastError = "Google Calendar event was modified externally."
                }
                return changed
            }
        } catch {
            return retryDraft(draft, message: approvalErrorMessage(from: error), clearCalendarMapping: false)
        }
    }

    private func retryDraft(_ draft: InboxDraft, message: String?, clearCalendarMapping: Bool = true) -> InboxDraft {
        var retry = draft
        retry.status = .calendarRetryRequired
        retry.lastError = message
        if clearCalendarMapping {
            retry.googleEventID = nil
            retry.googleEventURL = nil
        }
        return retry
    }

    private func approvalErrorMessage(from error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }

    private func appURL(for draft: InboxDraft) -> URL {
        appBaseURL.appendingPathComponent(draft.id.uuidString)
    }

    private func calendarEvent(
        for draft: InboxDraft,
        calendarID: String,
        dueDate: Date,
        household: HouseholdContext,
        reminderMinutesBefore: [Int]
    ) -> CalendarEventDraft {
        CalendarEventDraft(
            calendarID: calendarID,
            title: draft.title,
            dueDate: dueDate,
            notes: notes(for: draft, household: household),
            attendeeEmails: household.members.map(\.email),
            reminderMinutesBefore: reminderMinutesBefore,
            appURL: appURL(for: draft)
        )
    }

    private func snapshot(from event: CalendarEventDraft, reference: CalendarEventReference) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            title: event.title,
            dueDate: event.dueDate,
            notes: event.notes,
            url: reference.url,
            capturedAt: Date()
        )
    }

    private func notes(for draft: InboxDraft, household: HouseholdContext) -> String {
        var lines = [
            "Source: \(draft.source.subject)",
            "From: \(draft.source.from)",
            "Gmail message: \(draft.source.gmailMessageID)",
            "Open in Household Command Center: \(appURL(for: draft).absoluteString)"
        ]

        if let owner = household.member(withID: draft.ownerID) {
            lines.append("Owner: \(owner.displayName)")
        }

        if let area = household.area(withID: draft.areaID) {
            lines.append("Area: \(area.name)")
        }

        if let amount = draft.amount {
            lines.append("Amount: \(amount)")
        }

        if !draft.evidence.isEmpty {
            lines.append("Evidence: \(draft.evidence.joined(separator: " | "))")
        }

        lines.append("Extraction confidence: \(draft.extractionConfidence)")
        return lines.joined(separator: "\n")
    }
}

import Foundation

public struct LocalReminderPlan: Identifiable, Equatable, Sendable {
    public var draftID: UUID
    public var triggerDate: Date
    public var title: String
    public var body: String
    public var minutesBeforeDue: Int

    public var id: String {
        "\(draftID.uuidString)-\(minutesBeforeDue)"
    }

    public init(
        draftID: UUID,
        triggerDate: Date,
        title: String,
        body: String,
        minutesBeforeDue: Int
    ) {
        self.draftID = draftID
        self.triggerDate = triggerDate
        self.title = title
        self.body = body
        self.minutesBeforeDue = minutesBeforeDue
    }
}

public enum LocalReminderPlanner {
    public static func plans(
        drafts: [InboxDraft],
        household: HouseholdContext,
        now: Date = Date(),
        minimumLeadTime: TimeInterval = 60
    ) -> [LocalReminderPlan] {
        let analyzer = EmailIntelligenceAnalyzer()

        return drafts
            .flatMap { draft -> [LocalReminderPlan] in
                if let snoozedUntil = draft.snoozedUntil,
                   snoozedUntil.timeIntervalSince(now) >= minimumLeadTime,
                   isEligibleForSnoozeReturn(draft) {
                    return [
                        LocalReminderPlan(
                            draftID: draft.id,
                            triggerDate: snoozedUntil,
                            title: "Back on your list",
                            body: "\(draft.title) is ready for your attention again.",
                            minutesBeforeDue: 0
                        )
                    ]
                }

                guard isEligibleForDueDateReminder(draft, now: now), let dueDate = draft.dueDate else {
                    return []
                }
                let intelligence = analyzer.analyze(draft: draft, household: household, now: now)

                return Set(intelligence.recommendedReminderMinutesBefore)
                    .sorted(by: >)
                    .compactMap { minutesBeforeDue in
                        let triggerDate = dueDate.addingTimeInterval(-TimeInterval(minutesBeforeDue * 60))
                        guard triggerDate.timeIntervalSince(now) >= minimumLeadTime else { return nil }

                        return LocalReminderPlan(
                            draftID: draft.id,
                            triggerDate: triggerDate,
                            title: reminderTitle(for: draft, urgency: intelligence.urgency),
                            body: "\(draft.title) is due \(dueDate.formatted(date: .abbreviated, time: .shortened)).",
                            minutesBeforeDue: minutesBeforeDue
                        )
                    }
            }
            .sorted { left, right in
                if left.triggerDate == right.triggerDate {
                    return left.id < right.id
                }
                return left.triggerDate < right.triggerDate
            }
    }

    private static func isEligibleForDueDateReminder(_ draft: InboxDraft, now: Date) -> Bool {
        guard let dueDate = draft.dueDate, dueDate > now else { return false }
        guard draft.status != .rejected, draft.status != .approved else { return false }
        return !(draft.triageState?.isClosed ?? false)
            && !DraftSnoozeService.isCurrentlySnoozed(draft, now: now)
    }

    private static func isEligibleForSnoozeReturn(_ draft: InboxDraft) -> Bool {
        draft.status != .rejected
            && draft.status != .approved
            && !(draft.triageState?.isClosed ?? false)
    }

    private static func reminderTitle(for draft: InboxDraft, urgency: EmailUrgency) -> String {
        switch urgency {
        case .immediate:
            "Action due soon"
        case .soon:
            "Household reminder"
        case .normal, .low:
            "Upcoming household task"
        }
    }
}

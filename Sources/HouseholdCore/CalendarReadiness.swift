import Foundation

public enum CalendarReadinessState: String, CaseIterable, Equatable, Codable, Sendable {
    case needsDueDate
    case readyToApprove
    case scheduled
    case retryRequired
    case updateRequired
    case externalChange
    case rejected

    public var label: String {
        switch self {
        case .needsDueDate:
            "Needs Due Date"
        case .readyToApprove:
            "Ready"
        case .scheduled:
            "On Calendar"
        case .retryRequired:
            "Retry"
        case .updateRequired:
            "Needs Sync"
        case .externalChange:
            "External Change"
        case .rejected:
            "Rejected"
        }
    }
}

public struct CalendarReadiness: Equatable, Codable, Sendable {
    public var state: CalendarReadinessState
    public var detail: String
    public var canApproveToCalendar: Bool
    public var recommendedReminderMinutesBefore: [Int]

    public init(
        state: CalendarReadinessState,
        detail: String,
        canApproveToCalendar: Bool,
        recommendedReminderMinutesBefore: [Int]
    ) {
        self.state = state
        self.detail = detail
        self.canApproveToCalendar = canApproveToCalendar
        self.recommendedReminderMinutesBefore = recommendedReminderMinutesBefore
    }
}

public enum CalendarReadinessEvaluator {
    public static func evaluate(draft: InboxDraft, intelligence: EmailIntelligenceResult) -> CalendarReadiness {
        switch draft.status {
        case .rejected:
            return CalendarReadiness(
                state: .rejected,
                detail: "This draft was rejected and will not be written to Calendar.",
                canApproveToCalendar: false,
                recommendedReminderMinutesBefore: []
            )
        case .approved:
            return CalendarReadiness(
                state: .scheduled,
                detail: draft.googleEventID.map { "Google Calendar event \($0)" } ?? "Approved without a stored Calendar event ID.",
                canApproveToCalendar: false,
                recommendedReminderMinutesBefore: intelligence.recommendedReminderMinutesBefore
            )
        case .calendarRetryRequired:
            return CalendarReadiness(
                state: .retryRequired,
                detail: draft.lastError ?? "Calendar write failed and needs a retry.",
                canApproveToCalendar: draft.dueDate != nil,
                recommendedReminderMinutesBefore: intelligence.recommendedReminderMinutesBefore
            )
        case .calendarUpdateRequired:
            return CalendarReadiness(
                state: .updateRequired,
                detail: "This approved item changed locally and needs to sync to Google Calendar.",
                canApproveToCalendar: draft.dueDate != nil,
                recommendedReminderMinutesBefore: intelligence.recommendedReminderMinutesBefore
            )
        case .changedExternally:
            return CalendarReadiness(
                state: .externalChange,
                detail: draft.lastError ?? "The Google Calendar event changed outside the app.",
                canApproveToCalendar: false,
                recommendedReminderMinutesBefore: intelligence.recommendedReminderMinutesBefore
            )
        case .pendingApproval:
            guard draft.dueDate != nil else {
                return CalendarReadiness(
                    state: .needsDueDate,
                    detail: "Add a due date before creating a Calendar event.",
                    canApproveToCalendar: false,
                    recommendedReminderMinutesBefore: []
                )
            }

            return CalendarReadiness(
                state: .readyToApprove,
                detail: "Ready to approve to Google Calendar.",
                canApproveToCalendar: true,
                recommendedReminderMinutesBefore: intelligence.recommendedReminderMinutesBefore
            )
        }
    }
}

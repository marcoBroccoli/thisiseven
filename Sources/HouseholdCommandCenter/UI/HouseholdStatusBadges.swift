import SwiftUI
import HouseholdCore

struct AppStatusBadge: View {
    var label: String
    var color: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatusBadge: View {
    var status: InboxDraftStatus

    var body: some View {
        AppStatusBadge(label: label, color: color)
    }

    private var label: String {
        switch status {
        case .pendingApproval: "Pending"
        case .approved: "Approved"
        case .rejected: "Rejected"
        case .calendarRetryRequired: "Retry"
        case .calendarUpdateRequired: "Needs Sync"
        case .changedExternally: "External"
        }
    }

    private var color: Color {
        switch status {
        case .pendingApproval, .changedExternally: AppPalette.purple
        case .approved: AppPalette.teal
        case .rejected: AppPalette.red
        case .calendarRetryRequired, .calendarUpdateRequired: AppPalette.amberText
        }
    }
}

struct TriageBadge: View {
    var state: DraftTriageState

    var body: some View {
        AppStatusBadge(label: label, color: color)
    }

    private var label: String {
        switch state {
        case .active: "Active"
        case .waiting: "Waiting"
        case .done: "Done"
        case .notHousehold: "Not Household"
        }
    }

    private var color: Color {
        switch state {
        case .active: AppPalette.purple
        case .waiting: AppPalette.amberText
        case .done: AppPalette.teal
        case .notHousehold: AppPalette.secondaryText
        }
    }
}

struct ReplyStatusBadge: View {
    var status: ReplyWorkflowStatus

    var body: some View {
        AppStatusBadge(label: label, color: color)
    }

    private var label: String {
        switch status {
        case .none: "No Reply"
        case .needsReply: "Needs Reply"
        case .drafted: "Reply Drafted"
        case .copied: "Reply Copied"
        case .openedInGmail: "Opened Gmail"
        case .savedToGmailDraft: "Gmail Draft"
        case .sentManually: "Sent"
        case .done: "Reply Done"
        }
    }

    private var color: Color {
        switch status {
        case .none: AppPalette.secondaryText
        case .needsReply, .drafted: AppPalette.purple
        case .copied, .savedToGmailDraft: AppPalette.purpleDark
        case .openedInGmail: AppPalette.amberText
        case .sentManually, .done: AppPalette.teal
        }
    }
}

struct UrgencyBadge: View {
    var urgency: EmailUrgency

    var body: some View {
        AppStatusBadge(label: urgency.label, color: color)
    }

    private var color: Color {
        switch urgency {
        case .immediate: AppPalette.red
        case .soon: AppPalette.amberText
        case .normal: AppPalette.purple
        case .low: AppPalette.secondaryText
        }
    }
}

struct SnoozeStatusBadge: View {
    var body: some View {
        AppStatusBadge(label: "Deferred", color: AppPalette.amberText)
    }
}

struct RecurrenceBadge: View {
    var recurrence: HouseholdRecurrence

    var body: some View {
        AppStatusBadge(label: recurrence.label, color: AppPalette.teal)
    }
}

struct CalendarReadinessBadge: View {
    var state: CalendarReadinessState

    var body: some View {
        AppStatusBadge(label: state.label, color: color)
    }

    private var color: Color {
        switch state {
        case .needsDueDate, .retryRequired, .updateRequired: AppPalette.amberText
        case .readyToApprove, .externalChange: AppPalette.purple
        case .scheduled: AppPalette.teal
        case .rejected: AppPalette.red
        }
    }
}

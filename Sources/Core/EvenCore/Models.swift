import Foundation

// API DTOs mirroring docs/product/API.md. JSON is snake_case; the client
// applies key-conversion strategies, so properties stay camelCase.

public enum MemberColor: String, Codable, Sendable {
    case clay, teal
}

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var color: MemberColor
    public var isMe: Bool

    public init(id: UUID, displayName: String, color: MemberColor, isMe: Bool) {
        self.id = id
        self.displayName = displayName
        self.color = color
        self.isMe = isMe
    }
}

public struct Household: Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var inviteCode: String
    public var members: [Member]

    public init(id: UUID, name: String, inviteCode: String, members: [Member]) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.members = members
    }

    public var me: Member? {
        members.first(where: \.isMe)
    }

    public var partner: Member? {
        members.first(where: { !$0.isMe })
    }
}

public struct Week: Codable, Hashable, Sendable {
    public let id: UUID
    public var index: Int
    public var startedOn: String
    public var closedAt: Date?

    public init(id: UUID, index: Int, startedOn: String, closedAt: Date? = nil) {
        self.id = id
        self.index = index
        self.startedOn = startedOn
        self.closedAt = closedAt
    }
}

public enum TaskSection: String, Codable, CaseIterable, Sendable {
    case chore, admin
}

public enum Recurrence: String, Codable, CaseIterable, Sendable {
    case none, daily, every2Days = "every_2_days", weekly

    public var label: String {
        switch self {
        case .none: return "One-off"
        case .daily: return "Daily"
        case .every2Days: return "Every 2 days"
        case .weekly: return "Weekly"
        }
    }
}

public struct HouseholdTask: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var section: TaskSection
    public var ownerMemberId: UUID
    public var weight: Int
    public var recurrence: Recurrence
    public var dueOn: String?
    public var done: Bool
    public var doneByMemberId: UUID?
    public var metaLine: String
    public var googleEventUrl: String?
    public var calendarSyncState: CalendarSyncState?
    public var calendarLastSyncedAt: Date?
    public var calendarLastError: String?

    public init(
        id: UUID,
        title: String,
        section: TaskSection,
        ownerMemberId: UUID,
        weight: Int,
        recurrence: Recurrence,
        dueOn: String? = nil,
        done: Bool = false,
        doneByMemberId: UUID? = nil,
        metaLine: String,
        googleEventUrl: String? = nil,
        calendarSyncState: CalendarSyncState? = nil,
        calendarLastSyncedAt: Date? = nil,
        calendarLastError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.ownerMemberId = ownerMemberId
        self.weight = weight
        self.recurrence = recurrence
        self.dueOn = dueOn
        self.done = done
        self.doneByMemberId = doneByMemberId
        self.metaLine = metaLine
        self.googleEventUrl = googleEventUrl
        self.calendarSyncState = calendarSyncState
        self.calendarLastSyncedAt = calendarLastSyncedAt
        self.calendarLastError = calendarLastError
    }
}

public enum CalendarSyncState: String, Codable, Sendable {
    case notScheduled = "not_scheduled"
    case synced
    case externalChanged = "external_changed"
    case externalDeleted = "external_deleted"
    case retryRequired = "retry_required"

    public var label: String {
        switch self {
        case .notScheduled: return "Not scheduled"
        case .synced: return "Calendar synced"
        case .externalChanged: return "Updated in Calendar"
        case .externalDeleted: return "Removed in Calendar"
        case .retryRequired: return "Calendar needs retry"
        }
    }

    public var requiresResolution: Bool {
        switch self {
        case .externalChanged, .externalDeleted, .retryRequired:
            return true
        case .notScheduled, .synced:
            return false
        }
    }
}

public enum DraftReminder: String, Codable, CaseIterable, Sendable {
    case onDay = "on_day", oneDay = "1_day", threeDays = "3_days", oneWeek = "1_week"

    public var label: String {
        switch self {
        case .onDay: return "On the day"
        case .oneDay: return "1 day before"
        case .threeDays: return "3 days before"
        case .oneWeek: return "1 week before"
        }
    }
}

public enum DraftStatus: String, Codable, Sendable {
    case pending, approved, dismissed
}

public enum DraftReplyStatus: String, Codable, Sendable {
    case none
    case drafted
    case openedInGmail = "opened_in_gmail"
    case sentManually = "sent_manually"
    case done

    public var label: String {
        switch self {
        case .none: return "Reply needed"
        case .drafted: return "Draft ready"
        case .openedInGmail: return "Opened in Gmail"
        case .sentManually: return "Sent"
        case .done: return "Done"
        }
    }
}

public struct Draft: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var fromLabel: String
    public var subject: String
    public var summary: String?
    public var urgency: Int
    public var title: String
    public var ownerMemberId: UUID
    public var amountCents: Int?
    public var dueOn: String?
    public var reminder: DraftReminder
    public var status: DraftStatus
    public var createdByMemberId: UUID
    public var sourceFrom: String?
    public var sourcePreview: String?
    public var gmail: Bool?
    public var gmailMessageId: String?
    public var category: String?
    public var needsReply: Bool?
    public var suggestedReply: String?
    public var replyText: String?
    public var replyStatus: DraftReplyStatus?

    public init(
        id: UUID,
        fromLabel: String,
        subject: String,
        summary: String? = nil,
        urgency: Int,
        title: String,
        ownerMemberId: UUID,
        amountCents: Int? = nil,
        dueOn: String? = nil,
        reminder: DraftReminder,
        status: DraftStatus,
        createdByMemberId: UUID,
        sourceFrom: String? = nil,
        sourcePreview: String? = nil,
        gmail: Bool? = nil,
        gmailMessageId: String? = nil,
        category: String? = nil,
        needsReply: Bool? = nil,
        suggestedReply: String? = nil,
        replyText: String? = nil,
        replyStatus: DraftReplyStatus? = nil
    ) {
        self.id = id
        self.fromLabel = fromLabel
        self.subject = subject
        self.summary = summary
        self.urgency = urgency
        self.title = title
        self.ownerMemberId = ownerMemberId
        self.amountCents = amountCents
        self.dueOn = dueOn
        self.reminder = reminder
        self.status = status
        self.createdByMemberId = createdByMemberId
        self.sourceFrom = sourceFrom
        self.sourcePreview = sourcePreview
        self.gmail = gmail
        self.gmailMessageId = gmailMessageId
        self.category = category
        self.needsReply = needsReply
        self.suggestedReply = suggestedReply
        self.replyText = replyText
        self.replyStatus = replyStatus
    }

    public var isFromGmail: Bool {
        gmail ?? false
    }

    public var categoryKey: String {
        category ?? "other"
    }

    public var hasReplyWork: Bool {
        (needsReply ?? false) || !(suggestedReply?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(replyText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

public struct Expense: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var amountCents: Int
    public var paidByMemberId: UUID
    public var incurredOn: String
    public var settled: Bool
}

public struct Settlement: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var fromMemberId: UUID
    public var toMemberId: UUID
    public var amountCents: Int
    public var createdAt: Date
}

public struct Appreciation: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var fromMemberId: UUID
    public var toMemberId: UUID
    public var body: String?
    public var said: Bool
}

public struct Trade: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var taskId: UUID
    public var taskTitle: String
    public var fromMemberId: UUID
    public var toMemberId: UUID
    public var accepted: Bool
}

// MARK: - Endpoint payloads

public struct MeResponse: Codable, Sendable {
    public let userId: UUID
    public var member: Member?
    public var household: Household?
    public var week: Week?

    public init(userId: UUID, member: Member? = nil, household: Household? = nil, week: Week? = nil) {
        self.userId = userId
        self.member = member
        self.household = household
        self.week = week
    }
}

public struct Pebble: Codable, Hashable, Sendable {
    public var memberId: UUID
    public var weight: Int

    public init(memberId: UUID, weight: Int) {
        self.memberId = memberId
        self.weight = weight
    }
}

public struct SummarySection: Codable, Hashable, Sendable {
    public var key: TaskSection
    public var label: String
    public var tasks: [HouseholdTask]

    public init(key: TaskSection, label: String, tasks: [HouseholdTask]) {
        self.key = key
        self.label = label
        self.tasks = tasks
    }
}

public struct Summary: Codable, Hashable, Sendable {
    public var week: Week
    public var pebbles: [Pebble]
    public var percentMe: Int
    public var percentPartner: Int
    public var caption: String
    public var sections: [SummarySection]
    public var pendingDraftCount: Int

    public init(
        week: Week,
        pebbles: [Pebble],
        percentMe: Int,
        percentPartner: Int,
        caption: String,
        sections: [SummarySection],
        pendingDraftCount: Int
    ) {
        self.week = week
        self.pebbles = pebbles
        self.percentMe = percentMe
        self.percentPartner = percentPartner
        self.caption = caption
        self.sections = sections
        self.pendingDraftCount = pendingDraftCount
    }
}

public struct MoneyFeedItem: Codable, Identifiable, Hashable, Sendable {
    public var kind: Kind
    public enum Kind: String, Codable, Sendable { case expense, settlement }
    public let id: UUID
    public var title: String?
    public var amountCents: Int
    public var paidByMemberId: UUID?
    public var incurredOn: String?
    public var settled: Bool?
    public var fromMemberId: UUID?
    public var toMemberId: UUID?
    public var createdAt: Date?
}

public struct Money: Codable, Sendable {
    public var balanceCents: Int
    public var debtorMemberId: UUID?
    public var creditorMemberId: UUID?
    public var feed: [MoneyFeedItem]
}

public struct ResetRow: Codable, Hashable, Sendable {
    public var key: String
    public var label: String
    public var mePct: Int
    public var partnerPct: Int
}

public struct ResetSummary: Codable, Sendable {
    public var week: Week
    public var rows: [ResetRow]
    public var biggestCarry: String
    public var appreciations: [Appreciation]
    public var trades: [Trade]
}

public struct WeekCloseResponse: Codable, Sendable {
    public var closedWeek: Week
    public var newWeek: Week
}

public struct GoogleStatus: Codable, Sendable {
    public var connected: Bool
    public var email: String?
    public var lastSyncAt: Date?
    public var lastSyncCount: Int?
    public var calendarLastSyncAt: Date?
    // Live scan-job state — the app polls these while a sync runs.
    public var syncRunning: Bool?
    public var scanned: Int?
    public var classified: Int?
    public var created: Int?
    public var hasMore: Bool?

    public init(
        connected: Bool,
        email: String? = nil,
        lastSyncAt: Date? = nil,
        lastSyncCount: Int? = nil,
        calendarLastSyncAt: Date? = nil,
        syncRunning: Bool? = nil,
        scanned: Int? = nil,
        classified: Int? = nil,
        created: Int? = nil,
        hasMore: Bool? = nil
    ) {
        self.connected = connected
        self.email = email
        self.lastSyncAt = lastSyncAt
        self.lastSyncCount = lastSyncCount
        self.calendarLastSyncAt = calendarLastSyncAt
        self.syncRunning = syncRunning
        self.scanned = scanned
        self.classified = classified
        self.created = created
        self.hasMore = hasMore
    }

    public var isSyncing: Bool {
        syncRunning ?? false
    }
}

public struct GoogleSyncStart: Codable, Sendable {
    public var started: Bool?

    public init(started: Bool? = nil) {
        self.started = started
    }
}

/// One dated item on the shared calendar — a pending draft or a task.
public struct CalendarItem: Codable, Identifiable, Hashable, Sendable {
    public var kind: Kind
    public enum Kind: String, Codable, Sendable { case draft, task }
    /// A repeat gets a stable "task-id:occurrence-date" identity, so the
    /// schedule can show each calendar occurrence independently.
    public let id: String
    public var title: String
    public var category: String?
    public var ownerMemberId: UUID
    public var amountCents: Int?
    public var dueOn: String
    public var done: Bool?
    public var googleEventUrl: String?

    public init(
        kind: Kind,
        id: String,
        title: String,
        category: String? = nil,
        ownerMemberId: UUID,
        amountCents: Int? = nil,
        dueOn: String,
        done: Bool? = nil,
        googleEventUrl: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.category = category
        self.ownerMemberId = ownerMemberId
        self.amountCents = amountCents
        self.dueOn = dueOn
        self.done = done
        self.googleEventUrl = googleEventUrl
    }
}

public struct CalendarResponse: Codable, Sendable {
    public var from: String
    public var to: String
    public var items: [CalendarItem]

    public init(from: String, to: String, items: [CalendarItem]) {
        self.from = from
        self.to = to
        self.items = items
    }
}

public struct GoogleCalendarInfo: Codable, Sendable {
    public var calendarId: String
    public var shared: Bool
    public var shareUrl: String?
}

public struct CalendarSyncResult: Codable, Sendable {
    public var calendarId: String
    public var imported: Int
    public var updated: Int
    public var deleted: Int
    public var unchanged: Int
    public var lastSyncedAt: Date
}

public struct APIErrorBody: Codable, Sendable {
    public struct Inner: Codable, Sendable {
        public let code: String
        public let message: String
    }

    public let error: Inner
}

import Foundation

// API DTOs mirroring docs/product/API.md. JSON is snake_case; the client
// applies key-conversion strategies, so properties stay camelCase.

/// Member accent — `#RRGGBB`. Legacy API values `clay` / `teal` decode to the
/// terracotta / pine defaults.
public struct MemberColor: Hashable, Sendable, Codable, Equatable {
    public let hex: String

    public static let clay = MemberColor(hex: "#A6552F")
    public static let teal = MemberColor(hex: "#37756D")

    public init(hex: String) {
        self.hex = Self.normalize(hex)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(hex: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// 0xRRGGBB for `Color(hex:)` / widget helpers.
    public var rgb: UInt32 {
        let digits = hex.dropFirst()
        return UInt32(digits, radix: 16) ?? 0xA6552F
    }

    private static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "clay": return "#A6552F"
        case "teal": return "#37756D"
        default:
            let upper = trimmed.uppercased()
            if upper.hasPrefix("#"), upper.count == 7,
               upper.dropFirst().allSatisfy(\.isHexDigit)
            {
                return upper
            }
            return "#A6552F"
        }
    }
}

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var color: MemberColor
    public var isMe: Bool
    public var hasAvatar: Bool

    public init(
        id: UUID,
        displayName: String,
        color: MemberColor,
        isMe: Bool,
        hasAvatar: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.color = color
        self.isMe = isMe
        self.hasAvatar = hasAvatar
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

/// One line of the household switcher (`GET /v1/households`). A person may hold
/// several of these; only two people fit in each.
public struct HouseholdRow: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var memberCount: Int
    /// The caller created this household.
    public var isOwner: Bool
    /// The caller's member row *there* — one per household, never shared.
    public var myMemberId: UUID
    public var inviteCode: String
    /// The address of the outstanding email invite; absent when the free seat
    /// has nobody waiting, or when both seats are taken.
    public var pendingInviteEmail: String?

    public init(
        id: UUID,
        name: String,
        memberCount: Int,
        isOwner: Bool,
        myMemberId: UUID,
        inviteCode: String,
        pendingInviteEmail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
        self.isOwner = isOwner
        self.myMemberId = myMemberId
        self.inviteCode = inviteCode
        self.pendingInviteEmail = pendingInviteEmail
    }

    /// "1 of 2" / "2 of 2" — a household is a pair, always.
    public var seatsLine: String {
        "\(memberCount) of 2"
    }

    public var hasFreeSeat: Bool {
        memberCount < 2
    }
}

public enum InviteStatus: String, Codable, Sendable {
    case pending, accepted, declined, revoked

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InviteStatus(rawValue: raw) ?? .pending
    }
}

/// An invite is a record, not mail — evend sends nothing. Whoever signs in with
/// the matching address finds it waiting in `GET /v1/households`.
public struct HouseholdInvite: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var householdName: String
    public var invitedByName: String
    public var email: String
    public var status: InviteStatus
    public var createdAt: Date?

    public init(
        id: UUID,
        householdId: UUID,
        householdName: String,
        invitedByName: String,
        email: String,
        status: InviteStatus = .pending,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.householdName = householdName
        self.invitedByName = invitedByName
        self.email = email
        self.status = status
        self.createdAt = createdAt
    }
}

/// The answer to giving up your seat. `householdDeleted` when you were the last
/// one in — an empty household is not kept.
public struct LeaveHouseholdResult: Codable, Hashable, Sendable {
    public var ok: Bool
    public var householdDeleted: Bool

    public init(ok: Bool = true, householdDeleted: Bool = false) {
        self.ok = ok
        self.householdDeleted = householdDeleted
    }
}

/// Everything the switcher needs — membership not required, because a brand new
/// user has to see their invite before they belong anywhere.
public struct HouseholdsResponse: Codable, Hashable, Sendable {
    public var households: [HouseholdRow]
    public var invites: [HouseholdInvite]

    public init(households: [HouseholdRow] = [], invites: [HouseholdInvite] = []) {
        self.households = households
        self.invites = invites
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

    /// Days between two occurrences, or `nil` when the value does not repeat.
    public var intervalDays: Int? {
        switch self {
        case .none: return nil
        case .daily: return 1
        case .every2Days: return 2
        case .weekly: return 7
        }
    }

    /// Whether the checkbox belongs to a single day rather than the open week.
    /// Daily and every-two-day chores record one completion per occurrence.
    public var completesPerOccurrence: Bool {
        self == .daily || self == .every2Days
    }

    /// First scheduled day on or after `from`, or `nil` once the series has run
    /// out. Mirrors `nextOccurrence` in `backend/internal/api/tasks.go` — a
    /// repeat is a rule anchored on its due date, never a set of stored rows.
    public func nextOccurrence(
        anchor: Date,
        until: Date? = nil,
        from: Date,
        calendar: Calendar = .evenHousehold
    ) -> Date? {
        guard let interval = intervalDays else { return nil }
        let anchorDay = calendar.startOfDay(for: anchor)
        let fromDay = calendar.startOfDay(for: from)
        var occurrence = anchorDay
        if fromDay > anchorDay {
            let elapsed = calendar.dateComponents([.day], from: anchorDay, to: fromDay).day ?? 0
            let steps = (elapsed + interval - 1) / interval
            occurrence = calendar.date(byAdding: .day, value: steps * interval, to: anchorDay) ?? anchorDay
        }
        if let until, occurrence > calendar.startOfDay(for: until) { return nil }
        return occurrence
    }

    /// Last scheduled day of a bounded repeat. A count is what the household
    /// picked; the date is what every occurrence check reads, so the two
    /// spellings of "until when?" cannot disagree. Mirrors
    /// `resolveRecurrenceEnd` in `backend/internal/api/tasks.go`.
    public func recurrenceEnd(
        anchor: Date,
        until: Date? = nil,
        count: Int? = nil,
        calendar: Calendar = .evenHousehold
    ) -> Date? {
        guard let interval = intervalDays else { return nil }
        if let count {
            return calendar.date(
                byAdding: .day,
                value: (count - 1) * interval,
                to: calendar.startOfDay(for: anchor)
            )
        }
        return until.map { calendar.startOfDay(for: $0) }
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
    /// Last scheduled day of a bounded repeat (`nil` = runs until deleted).
    /// Derived server-side from `recurrenceCount` when a count was picked.
    public var recurrenceUntil: String?
    /// How many occurrences the household asked for, when they expressed the
    /// bound as a number of times rather than a date.
    public var recurrenceCount: Int?
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
        recurrenceUntil: String? = nil,
        recurrenceCount: Int? = nil,
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
        self.recurrenceUntil = recurrenceUntil
        self.recurrenceCount = recurrenceCount
        self.done = done
        self.doneByMemberId = doneByMemberId
        self.metaLine = metaLine
        self.googleEventUrl = googleEventUrl
        self.calendarSyncState = calendarSyncState
        self.calendarLastSyncedAt = calendarLastSyncedAt
        self.calendarLastError = calendarLastError
    }

    /// Recomputes the row meta from structured fields so a stale stored
    /// `metaLine` (e.g. `"WEEKLY"` after create when `dueOn` is present) cannot
    /// stick in the UI. Preserves an origin prefix from `metaLine` when present.
    public var resolvedMetaLine: String {
        Self.makeMetaLine(
            originLabel: Self.originLabel(fromMetaLine: metaLine),
            dueOn: dueOn,
            recurrence: recurrence,
            recurrenceUntil: recurrenceUntil,
            recurrenceCount: recurrenceCount
        )
    }

    /// Mirrors `metaLine` in `backend/internal/api/types.go` — small-caps row
    /// under the title, e.g. `"VATTENFALL · TOMORROW · WEEKLY · 6 TIMES"`.
    public static func makeMetaLine(
        originLabel: String? = nil,
        dueOn: String?,
        recurrence: Recurrence,
        recurrenceUntil: String? = nil,
        recurrenceCount: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .evenHousehold
    ) -> String {
        var parts: [String] = []
        if let originLabel, !originLabel.isEmpty {
            parts.append(originLabel.uppercased())
        }

        let until = recurrenceUntil.flatMap(calendar.evenParseCivilDate)
        if let day = metaDueDay(
            dueOn: dueOn, recurrence: recurrence, until: until, now: now, calendar: calendar
        ) {
            parts.append(duePhrase(for: day, now: now, calendar: calendar))
        }

        switch recurrence {
        case .none: break
        case .daily: parts.append("DAILY")
        case .every2Days: parts.append("EVERY 2 DAYS")
        case .weekly: parts.append("WEEKLY")
        }

        if recurrence.intervalDays != nil {
            if let recurrenceCount {
                parts.append("\(recurrenceCount) TIMES")
            } else if let until {
                parts.append("UNTIL " + monthTip(for: until, calendar: calendar))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// The day the row describes. A repeat points at its **next** occurrence, so
    /// a weekly chore that is still on schedule never reads as overdue. Daily and
    /// every-two-day repeats have no useful date — they are only listed on a day
    /// they are due.
    private static func metaDueDay(
        dueOn: String?,
        recurrence: Recurrence,
        until: Date?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let due = dueOn.flatMap(calendar.evenParseCivilDate)
        switch recurrence {
        case .none: return due
        case .daily, .every2Days: return nil
        case .weekly:
            // Without a due date the anchor is the capture date, which the API
            // does not return — omit the tip rather than guess at "today".
            guard let due else { return nil }
            return recurrence.nextOccurrence(
                anchor: due, until: until, from: now, calendar: calendar
            )
        }
    }

    private static func duePhrase(for day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "TODAY"
        case 1: return "TOMORROW"
        case -1: return "1 DAY OVER"
        case ..<(-1): return "\(-days) DAYS OVER"
        default: return monthTip(for: day, calendar: calendar)
        }
    }

    private static func monthTip(for day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: day).uppercased()
    }

    /// First ` · ` segment of a server `metaLine` when it looks like an origin
    /// label (e.g. `VATTENFALL`), not a due/recurrence phrase.
    public static func originLabel(fromMetaLine metaLine: String) -> String? {
        let first = metaLine
            .split(separator: "·", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty, !looksLikeDueOrRecurrencePhrase(first) else { return nil }
        return first
    }

    private static func looksLikeDueOrRecurrencePhrase(_ segment: String) -> Bool {
        let u = segment.uppercased()
        if u == "TODAY" || u == "TOMORROW" || u == "WEEKLY" || u == "DAILY"
            || u == "EVERY 2 DAYS" || u.hasPrefix("EVERY ")
        {
            return true
        }
        if u.contains(" OVER") { return true }
        // Month tip: "AUG 12", "JAN 3"
        let months = [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        ]
        for month in months where u.hasPrefix(month + " ") || u == month {
            return true
        }
        return false
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

    public init(
        id: UUID,
        fromMemberId: UUID,
        toMemberId: UUID,
        body: String?,
        said: Bool
    ) {
        self.id = id
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.body = body
        self.said = said
    }
}

public struct Trade: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var taskId: UUID
    public var taskTitle: String
    public var fromMemberId: UUID
    public var toMemberId: UUID
    public var accepted: Bool

    public init(
        id: UUID,
        taskId: UUID,
        taskTitle: String,
        fromMemberId: UUID,
        toMemberId: UUID,
        accepted: Bool
    ) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.accepted = accepted
    }
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

public struct ResetRow: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var mePct: Int
    public var partnerPct: Int

    public var id: String { key }

    public init(key: String, label: String, mePct: Int, partnerPct: Int) {
        self.key = key
        self.label = label
        self.mePct = mePct
        self.partnerPct = partnerPct
    }
}

public struct ResetSummary: Codable, Sendable, Equatable {
    public var week: Week
    public var rows: [ResetRow]
    public var biggestCarry: String
    public var appreciations: [Appreciation]
    public var trades: [Trade]

    public init(
        week: Week,
        rows: [ResetRow],
        biggestCarry: String,
        appreciations: [Appreciation],
        trades: [Trade]
    ) {
        self.week = week
        self.rows = rows
        self.biggestCarry = biggestCarry
        self.appreciations = appreciations
        self.trades = trades
    }
}

public struct WeekCloseResponse: Codable, Sendable, Equatable {
    public var closedWeek: Week
    public var newWeek: Week

    public init(closedWeek: Week, newWeek: Week) {
        self.closedWeek = closedWeek
        self.newWeek = newWeek
    }
}

public struct GoogleStatus: Codable, Sendable {
    /// Whether *this* member has connected their own mailbox. Each member
    /// connects their own Gmail; only the Calendar is shared.
    public var connected: Bool
    /// Whether the partner has connected theirs — a bare flag, so the app can
    /// explain the shared calendar without ever naming their address.
    public var partnerConnected: Bool?
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
        partnerConnected: Bool? = nil,
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
        self.partnerConnected = partnerConnected
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

    public var hasPartnerConnected: Bool {
        partnerConnected ?? false
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

/// The household's shared calendar as seen by *this* member. Google gives a
/// secondary calendar exactly one owning account, so the mirror has an owner
/// and — for the other partner — a one-tap "add to my Google" confirm.
public struct GoogleCalendarInfo: Codable, Sendable, Equatable {
    public var calendarId: String
    public var shared: Bool
    public var shareUrl: String?
    /// The caller's Google account owns the calendar: nothing to add.
    public var owner: Bool?
    /// Already on the caller's Google Calendar list (owners always are).
    public var listed: Bool?
    /// Connected + a shared calendar exists + neither owner nor listed.
    public var canAdd: Bool?

    public init(
        calendarId: String,
        shared: Bool,
        shareUrl: String? = nil,
        owner: Bool? = nil,
        listed: Bool? = nil,
        canAdd: Bool? = nil
    ) {
        self.calendarId = calendarId
        self.shared = shared
        self.shareUrl = shareUrl
        self.owner = owner
        self.listed = listed
        self.canAdd = canAdd
    }

    public var isOwner: Bool { owner ?? false }
    public var isListed: Bool { listed ?? false }
    /// Older servers omit the flag; never offer a confirm we cannot fulfil.
    public var offersAdd: Bool { canAdd ?? false }
}

/// Result of the partner's confirm — the calendar is on their Google now.
public struct GoogleCalendarAddResult: Codable, Sendable, Equatable {
    public var calendarId: String
    public var listed: Bool
    public var owner: Bool?
    /// The recorded owner had no connection left, so the caller took the
    /// calendar over instead of subscribing to a dead one.
    public var adopted: Bool?

    public init(calendarId: String, listed: Bool, owner: Bool? = nil, adopted: Bool? = nil) {
        self.calendarId = calendarId
        self.listed = listed
        self.owner = owner
        self.adopted = adopted
    }
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

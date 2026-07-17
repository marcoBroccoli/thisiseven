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
}

public struct Household: Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var inviteCode: String
    public var members: [Member]

    public var me: Member? { members.first(where: \.isMe) }
    public var partner: Member? { members.first(where: { !$0.isMe }) }
}

public struct Week: Codable, Hashable, Sendable {
    public let id: UUID
    public var index: Int
    public var startedOn: String
    public var closedAt: Date?
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
}

public struct Pebble: Codable, Hashable, Sendable {
    public var memberId: UUID
    public var weight: Int
}

public struct SummarySection: Codable, Hashable, Sendable {
    public var key: TaskSection
    public var label: String
    public var tasks: [HouseholdTask]
}

public struct Summary: Codable, Sendable {
    public var week: Week
    public var pebbles: [Pebble]
    public var percentMe: Int
    public var percentPartner: Int
    public var caption: String
    public var sections: [SummarySection]
    public var pendingDraftCount: Int
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

public struct APIErrorBody: Codable, Sendable {
    public struct Inner: Codable, Sendable {
        public let code: String
        public let message: String
    }
    public let error: Inner
}

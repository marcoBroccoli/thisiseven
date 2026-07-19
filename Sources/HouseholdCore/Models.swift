import Foundation

public struct HouseholdMember: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: UUID
    public var displayName: String
    public var email: String

    public init(id: UUID, displayName: String, email: String) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}

public struct HouseholdArea: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var defaultOwnerID: UUID?

    public init(id: UUID, name: String, defaultOwnerID: UUID?) {
        self.id = id
        self.name = name
        self.defaultOwnerID = defaultOwnerID
    }
}

public struct HouseholdContext: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var members: [HouseholdMember]
    public var areas: [HouseholdArea]
    public var sharedCalendarID: String?

    public init(id: UUID, members: [HouseholdMember], areas: [HouseholdArea], sharedCalendarID: String?) {
        self.id = id
        self.members = members
        self.areas = areas
        self.sharedCalendarID = sharedCalendarID
    }

    public func area(withID id: UUID?) -> HouseholdArea? {
        guard let id else { return nil }
        return areas.first { $0.id == id }
    }

    public func member(withID id: UUID?) -> HouseholdMember? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }
}

public struct SourceEmail: Equatable, Hashable, Codable, Sendable {
    public var gmailMessageID: String
    public var subject: String
    public var from: String
    public var receivedAt: Date
    public var label: String
    public var bodyPreview: String

    public init(gmailMessageID: String, subject: String, from: String, receivedAt: Date, label: String, bodyPreview: String) {
        self.gmailMessageID = gmailMessageID
        self.subject = subject
        self.from = from
        self.receivedAt = receivedAt
        self.label = label
        self.bodyPreview = bodyPreview
    }
}

public struct ExtractionResult: Equatable, Codable, Sendable {
    public var title: String?
    public var dueDate: Date?
    public var amount: Decimal?
    public var suggestedOwnerID: UUID?
    public var areaID: UUID?
    public var evidence: [String]
    public var confidence: Double

    public init(
        title: String?,
        dueDate: Date?,
        amount: Decimal?,
        suggestedOwnerID: UUID?,
        areaID: UUID?,
        evidence: [String],
        confidence: Double
    ) {
        self.title = title
        self.dueDate = dueDate
        self.amount = amount
        self.suggestedOwnerID = suggestedOwnerID
        self.areaID = areaID
        self.evidence = evidence
        self.confidence = confidence
    }
}

public enum InboxDraftStatus: String, Equatable, Codable, CaseIterable, Sendable {
    case pendingApproval
    case approved
    case rejected
    case calendarRetryRequired
    case calendarUpdateRequired
    case changedExternally
}

public enum DraftTriageState: String, Equatable, Codable, CaseIterable, Sendable {
    case active
    case waiting
    case done
    case notHousehold

    public var isClosed: Bool {
        self == .done || self == .notHousehold
    }
}

public enum HouseholdRecurrence: String, Equatable, Codable, CaseIterable, Sendable {
    case weekly
    case fortnightly
    case monthly
    case quarterly

    public var label: String {
        switch self {
        case .weekly: "Every week"
        case .fortnightly: "Every 2 weeks"
        case .monthly: "Every month"
        case .quarterly: "Every 3 months"
        }
    }

    public var googleCalendarRule: String {
        switch self {
        case .weekly: "RRULE:FREQ=WEEKLY"
        case .fortnightly: "RRULE:FREQ=WEEKLY;INTERVAL=2"
        case .monthly: "RRULE:FREQ=MONTHLY"
        case .quarterly: "RRULE:FREQ=MONTHLY;INTERVAL=3"
        }
    }
}

public enum ReplyWorkflowStatus: String, Equatable, Codable, CaseIterable, Sendable {
    case none
    case needsReply
    case drafted
    case copied
    case openedInGmail
    case savedToGmailDraft
    case sentManually
    case done

    public var requiresReplyAction: Bool {
        switch self {
        case .needsReply, .drafted, .copied, .openedInGmail, .savedToGmailDraft:
            true
        case .none, .sentManually, .done:
            false
        }
    }
}

public struct InboxDraft: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var source: SourceEmail
    public var title: String
    public var dueDate: Date?
    public var amount: Decimal?
    public var ownerID: UUID?
    public var areaID: UUID?
    public var extractionConfidence: Double
    public var evidence: [String]
    public var status: InboxDraftStatus
    public var approverID: UUID?
    public var googleEventID: String?
    public var googleEventURL: URL?
    public var lastError: String?
    public var triageState: DraftTriageState?
    public var replyStatus: ReplyWorkflowStatus?
    public var gmailReplyDraftID: String?
    public var snoozedUntil: Date?
    public var recurrence: HouseholdRecurrence?
    public var calendarLastSyncedSnapshot: CalendarEventSnapshot?
    public var calendarExternalSnapshot: CalendarEventSnapshot?

    public init(
        id: UUID,
        source: SourceEmail,
        title: String,
        dueDate: Date?,
        amount: Decimal?,
        ownerID: UUID?,
        areaID: UUID?,
        extractionConfidence: Double,
        evidence: [String],
        status: InboxDraftStatus,
        approverID: UUID?,
        googleEventID: String?,
        googleEventURL: URL?,
        lastError: String?,
        triageState: DraftTriageState? = .active,
        replyStatus: ReplyWorkflowStatus? = ReplyWorkflowStatus.none,
        gmailReplyDraftID: String? = nil,
        snoozedUntil: Date? = nil,
        recurrence: HouseholdRecurrence? = nil,
        calendarLastSyncedSnapshot: CalendarEventSnapshot? = nil,
        calendarExternalSnapshot: CalendarEventSnapshot? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.dueDate = dueDate
        self.amount = amount
        self.ownerID = ownerID
        self.areaID = areaID
        self.extractionConfidence = extractionConfidence
        self.evidence = evidence
        self.status = status
        self.approverID = approverID
        self.googleEventID = googleEventID
        self.googleEventURL = googleEventURL
        self.lastError = lastError
        self.triageState = triageState
        self.replyStatus = replyStatus
        self.gmailReplyDraftID = gmailReplyDraftID
        self.snoozedUntil = snoozedUntil
        self.recurrence = recurrence
        self.calendarLastSyncedSnapshot = calendarLastSyncedSnapshot
        self.calendarExternalSnapshot = calendarExternalSnapshot
    }

    public static func pending(
        id: UUID = UUID(),
        source: SourceEmail,
        title: String,
        dueDate: Date?,
        amount: Decimal?,
        ownerID: UUID?,
        areaID: UUID?,
        extractionConfidence: Double,
        evidence: [String]
    ) -> InboxDraft {
        InboxDraft(
            id: id,
            source: source,
            title: title,
            dueDate: dueDate,
            amount: amount,
            ownerID: ownerID,
            areaID: areaID,
            extractionConfidence: extractionConfidence,
            evidence: evidence,
            status: .pendingApproval,
            approverID: nil,
            googleEventID: nil,
            googleEventURL: nil,
            lastError: nil,
            triageState: .active,
            replyStatus: ReplyWorkflowStatus.none,
            gmailReplyDraftID: nil,
            snoozedUntil: nil,
            recurrence: nil,
            calendarLastSyncedSnapshot: nil,
            calendarExternalSnapshot: nil
        )
    }
}

import Foundation

public enum EmailUrgency: String, CaseIterable, Equatable, Codable, Sendable {
    case immediate
    case soon
    case normal
    case low

    public var label: String {
        switch self {
        case .immediate:
            "Urgent"
        case .soon:
            "Soon"
        case .normal:
            "Normal"
        case .low:
            "Low"
        }
    }

    public var sortPriority: Int {
        switch self {
        case .immediate:
            0
        case .soon:
            1
        case .normal:
            2
        case .low:
            3
        }
    }
}

public enum EmailTriageTag: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
    case bill
    case renewal
    case subscription
    case appointment
    case calendar
    case replyNeeded
    case bankingCandidate
    case admin
    case lowPriority
    case calendarSync

    public var label: String {
        switch self {
        case .bill:
            "Bill"
        case .renewal:
            "Renewal"
        case .subscription:
            "Subscription"
        case .appointment:
            "Appointment"
        case .calendar:
            "Calendar"
        case .replyNeeded:
            "Reply"
        case .bankingCandidate:
            "Banking"
        case .admin:
            "Admin"
        case .lowPriority:
            "Low Priority"
        case .calendarSync:
            "Calendar Sync"
        }
    }
}

public enum EmailPrimaryAction: String, CaseIterable, Equatable, Codable, Sendable {
    case payAndReply
    case pay
    case scheduleAndReply
    case approveToCalendar
    case reply
    case review
    case ignore
    case fixCalendarSync

    public var label: String {
        switch self {
        case .payAndReply:
            "Pay, then reply"
        case .pay:
            "Pay or review bill"
        case .scheduleAndReply:
            "Schedule, then reply"
        case .approveToCalendar:
            "Approve to Calendar"
        case .reply:
            "Reply"
        case .review:
            "Review"
        case .ignore:
            "Ignore"
        case .fixCalendarSync:
            "Fix Calendar sync"
        }
    }
}

public struct SuggestedEmailReply: Equatable, Codable, Sendable {
    public var subject: String
    public var body: String
    public var confidence: Double

    public init(subject: String, body: String, confidence: Double) {
        self.subject = subject
        self.body = body
        self.confidence = confidence
    }
}

public struct EmailIntelligenceResult: Equatable, Codable, Sendable {
    public var urgency: EmailUrgency
    public var tags: [EmailTriageTag]
    public var primaryAction: EmailPrimaryAction
    public var summary: String
    public var reason: String
    public var suggestedReply: SuggestedEmailReply?
    public var recommendedReminderMinutesBefore: [Int]

    public init(
        urgency: EmailUrgency,
        tags: [EmailTriageTag],
        primaryAction: EmailPrimaryAction,
        summary: String,
        reason: String,
        suggestedReply: SuggestedEmailReply?,
        recommendedReminderMinutesBefore: [Int]
    ) {
        self.urgency = urgency
        self.tags = tags
        self.primaryAction = primaryAction
        self.summary = summary
        self.reason = reason
        self.suggestedReply = suggestedReply
        self.recommendedReminderMinutesBefore = recommendedReminderMinutesBefore
    }
}

public struct EmailIntelligenceAnalyzer: Sendable {
    public init() {}

    public func analyze(draft: InboxDraft, household: HouseholdContext, now: Date = Date()) -> EmailIntelligenceResult {
        let text = searchableText(for: draft)
        let tags = tags(for: draft, text: text)
        let urgency = urgency(for: draft, text: text, now: now)
        let action = primaryAction(for: draft, tags: tags)
        let reply = suggestedReply(for: draft, action: action, tags: tags)

        return EmailIntelligenceResult(
            urgency: urgency,
            tags: tags,
            primaryAction: action,
            summary: summary(for: draft, action: action, tags: tags, household: household),
            reason: reason(for: draft, urgency: urgency, tags: tags, now: now),
            suggestedReply: reply,
            recommendedReminderMinutesBefore: HouseholdReminderPolicy.recommendedReminderMinutesBefore(
                urgency: urgency,
                dueDate: draft.dueDate
            )
        )
    }

    private func searchableText(for draft: InboxDraft) -> String {
        [
            draft.title,
            draft.source.subject,
            draft.source.from,
            draft.source.label,
            draft.source.bodyPreview,
            draft.evidence.joined(separator: " ")
        ]
            .joined(separator: " ")
            .lowercased()
    }

    private func tags(for draft: InboxDraft, text: String) -> [EmailTriageTag] {
        var tags: [EmailTriageTag] = []

        if draft.status == .calendarRetryRequired || draft.status == .calendarUpdateRequired || draft.status == .changedExternally {
            tags.append(.calendarSync)
        }

        let billKeywords = ["bill", "invoice", "payment", "pay ", "rent", "utility", "utilities", "tax", "insurance"]
        if draft.amount != nil || text.containsAny(of: billKeywords) {
            tags.append(.bill)
        }

        if text.containsAny(of: ["renew", "renewal", "expires", "expiry"]) {
            tags.append(.renewal)
        }

        if text.containsAny(of: ["subscription", "membership", "plan renews", "monthly plan"]) {
            tags.append(.subscription)
        }

        if text.containsAny(of: ["appointment", "dentist", "doctor", "booking", "reservation", "visit"]) {
            tags.append(.appointment)
        }

        if draft.dueDate != nil || tags.contains(.appointment) {
            tags.append(.calendar)
        }

        if text.contains("?") || text.containsAny(of: ["reply", "respond", "confirm", "rsvp", "let us know", "can you"]) {
            tags.append(.replyNeeded)
        }

        if draft.amount != nil && text.containsAny(of: ["bill", "invoice", "payment", "pay", "rent", "insurance", "subscription", "renewal", "bank", "bunq"]) {
            tags.append(.bankingCandidate)
        }

        if text.containsAny(of: ["form", "document", "school", "permit", "tax", "admin"]) {
            tags.append(.admin)
        }

        if text.containsAny(of: ["newsletter", "promotion", "discount", "unsubscribe", "sale ends"]) && !tags.contains(.bill) {
            tags.append(.lowPriority)
        }

        return Array(OrderedSet(tags))
    }

    private func urgency(for draft: InboxDraft, text: String, now: Date) -> EmailUrgency {
        if draft.status == .calendarRetryRequired || draft.status == .calendarUpdateRequired || draft.status == .changedExternally {
            return .immediate
        }

        if text.containsAny(of: ["urgent", "overdue", "final notice", "past due", "last reminder", "action required"]) {
            return .immediate
        }

        guard let dueDate = draft.dueDate else {
            return text.containsAny(of: ["reply", "confirm", "respond"]) ? .normal : .low
        }

        let secondsUntilDue = dueDate.timeIntervalSince(now)
        if secondsUntilDue <= 86_400 {
            return .immediate
        }
        if secondsUntilDue <= 2 * 86_400 {
            return .soon
        }
        if secondsUntilDue <= 7 * 86_400 {
            return .normal
        }
        return .low
    }

    private func primaryAction(for draft: InboxDraft, tags: [EmailTriageTag]) -> EmailPrimaryAction {
        if draft.status == .calendarRetryRequired || draft.status == .calendarUpdateRequired || draft.status == .changedExternally {
            return .fixCalendarSync
        }

        if tags.contains(.bill) && tags.contains(.replyNeeded) {
            return .payAndReply
        }

        if tags.contains(.appointment) && tags.contains(.replyNeeded) {
            return .scheduleAndReply
        }

        if tags.contains(.replyNeeded) {
            return .reply
        }

        if tags.contains(.bill) {
            return .pay
        }

        if tags.contains(.calendar) {
            return .approveToCalendar
        }

        if tags.contains(.lowPriority) {
            return .ignore
        }

        return .review
    }

    private func suggestedReply(
        for draft: InboxDraft,
        action: EmailPrimaryAction,
        tags: [EmailTriageTag]
    ) -> SuggestedEmailReply? {
        guard [.payAndReply, .scheduleAndReply, .reply].contains(action) else {
            return nil
        }

        let subject = draft.title.lowercased().hasPrefix("re:") ? draft.title : "Re: \(draft.title)"
        let body: String

        switch action {
        case .payAndReply:
            body = "Hi,\n\nThanks for the reminder. I’ll take care of this and will follow up once it is complete.\n\nBest,"
        case .scheduleAndReply:
            body = "Hi,\n\nThanks for checking. I can confirm this and will keep the appointment on the calendar.\n\nBest,"
        case .reply:
            if tags.contains(.admin) {
                body = "Hi,\n\nThanks for sending this over. I’ll review it and get back to you shortly.\n\nBest,"
            } else {
                body = "Hi,\n\nThanks for the note. I’ll check this and follow up shortly.\n\nBest,"
            }
        default:
            return nil
        }

        return SuggestedEmailReply(subject: subject, body: body, confidence: 0.72)
    }

    private func summary(
        for draft: InboxDraft,
        action: EmailPrimaryAction,
        tags: [EmailTriageTag],
        household: HouseholdContext
    ) -> String {
        var parts = [action.label]

        if let amount = draft.amount {
            parts.append("amount \(amount)")
        }

        if let area = household.area(withID: draft.areaID) {
            parts.append(area.name)
        } else if tags.contains(.admin) {
            parts.append("admin")
        }

        return parts.joined(separator: " · ")
    }

    private func reason(for draft: InboxDraft, urgency: EmailUrgency, tags: [EmailTriageTag], now: Date) -> String {
        if draft.status == .calendarRetryRequired {
            return "The Calendar write failed and needs a retry."
        }

        if draft.status == .calendarUpdateRequired {
            return "Local edits need to be pushed to the existing Google Calendar event."
        }

        if draft.status == .changedExternally {
            return "The Google Calendar event changed outside the app."
        }

        if let dueDate = draft.dueDate {
            let dayCount = Int(ceil(dueDate.timeIntervalSince(now) / 86_400))
            if dayCount <= 0 {
                return "Due today or overdue."
            }
            return "Due in \(dayCount) day\(dayCount == 1 ? "" : "s")."
        }

        if tags.contains(.replyNeeded) {
            return "The email appears to need a human reply."
        }

        return "No due date detected; keep for review."
    }
}

public enum HouseholdReminderPolicy {
    public static func recommendedReminderMinutesBefore(urgency: EmailUrgency, dueDate: Date?) -> [Int] {
        guard dueDate != nil else {
            return []
        }

        switch urgency {
        case .immediate:
            return [60, 15]
        case .soon:
            return [1_440, 60]
        case .normal:
            return [2_880, 1_440]
        case .low:
            return [1_440]
        }
    }
}

private struct OrderedSet<Element: Hashable>: Sequence {
    private var elements: [Element] = []

    init(_ values: [Element]) {
        var seen: Set<Element> = []
        elements = values.filter { seen.insert($0).inserted }
    }

    func makeIterator() -> Array<Element>.Iterator {
        elements.makeIterator()
    }
}

private extension String {
    func containsAny(of needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}

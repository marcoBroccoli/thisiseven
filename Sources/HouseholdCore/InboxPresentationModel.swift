import Foundation

public struct InboxPresentationModel: Equatable, Sendable {
    public private(set) var drafts: [InboxDraft]
    public private(set) var selectedDraftID: UUID?

    public init(drafts: [InboxDraft]) {
        self.drafts = drafts
        self.selectedDraftID = drafts.first?.id
    }

    public var selectedDraft: InboxDraft? {
        guard let selectedDraftID else { return nil }
        return drafts.first { $0.id == selectedDraftID }
    }

    public var pendingApprovalCount: Int {
        drafts.filter { $0.status == .pendingApproval }.count
    }

    public var approvedCount: Int {
        drafts.filter { $0.status == .approved }.count
    }

    public var retryRequiredCount: Int {
        drafts.filter { $0.status == .calendarRetryRequired }.count
    }

    public var changedExternallyCount: Int {
        drafts.filter { $0.status == .changedExternally }.count
    }

    public var financeObligationCount: Int {
        drafts.filter { $0.amount != nil }.count
    }

    public mutating func selectDraft(id: UUID) {
        guard drafts.contains(where: { $0.id == id }) else { return }
        selectedDraftID = id
    }

    public mutating func replaceDraft(_ draft: InboxDraft) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }

        if selectedDraftID == nil {
            selectedDraftID = draft.id
        }
    }

    public func triageBuckets(household: HouseholdContext, now: Date = Date()) -> [InboxTriageBucket] {
        let analyzer = EmailIntelligenceAnalyzer()
        let openDrafts = drafts.filter { !($0.triageState?.isClosed ?? false) }
        let analyzedDrafts = openDrafts.map { draft in
            AnalyzedDraft(
                draft: draft,
                intelligence: analyzer.analyze(draft: draft, household: household, now: now)
            )
        }
        var remainingIDs = Set(openDrafts.map(\.id))
        var buckets: [InboxTriageBucket] = []

        func appendBucket(
            title: String,
            systemImage: String,
            matching predicate: (AnalyzedDraft) -> Bool
        ) {
            let matches = analyzedDrafts
                .filter { remainingIDs.contains($0.draft.id) && predicate($0) }
                .sortedByTriagePriority()

            guard !matches.isEmpty else { return }
            matches.forEach { remainingIDs.remove($0.draft.id) }
            buckets.append(InboxTriageBucket(
                title: title,
                systemImage: systemImage,
                drafts: matches.map(\.draft)
            ))
        }

        appendBucket(title: "Waiting", systemImage: "hourglass") {
            $0.draft.triageState == .waiting
        }
        appendBucket(title: "Calendar Sync", systemImage: "calendar.badge.exclamationmark") {
            $0.intelligence.tags.contains(.calendarSync)
        }
        appendBucket(title: "Urgent", systemImage: "exclamationmark.triangle") {
            $0.intelligence.urgency == .immediate
        }
        appendBucket(title: "Needs Reply", systemImage: "arrowshape.turn.up.left") {
            if let replyStatus = $0.draft.replyStatus, replyStatus != .none {
                return replyStatus.requiresReplyAction
            }

            return $0.intelligence.tags.contains(.replyNeeded)
        }
        appendBucket(title: "Bills", systemImage: "creditcard") {
            $0.intelligence.tags.contains(.bill)
                || $0.intelligence.tags.contains(.bankingCandidate)
                || $0.intelligence.tags.contains(.subscription)
                || $0.intelligence.tags.contains(.renewal)
        }
        appendBucket(title: "Calendar", systemImage: "calendar") {
            $0.intelligence.tags.contains(.calendar)
        }
        appendBucket(title: "Low Priority", systemImage: "tray") {
            $0.intelligence.tags.contains(.lowPriority) || $0.intelligence.urgency == .low
        }
        appendBucket(title: "Review", systemImage: "checklist") { _ in
            true
        }

        return buckets
    }
}

public struct InboxTriageBucket: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var systemImage: String
    public var drafts: [InboxDraft]

    public init(title: String, systemImage: String, drafts: [InboxDraft]) {
        self.title = title
        self.systemImage = systemImage
        self.drafts = drafts
    }
}

private struct AnalyzedDraft {
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult
}

private extension Array where Element == AnalyzedDraft {
    func sortedByTriagePriority() -> [AnalyzedDraft] {
        sorted { lhs, rhs in
            if lhs.intelligence.urgency.sortPriority != rhs.intelligence.urgency.sortPriority {
                return lhs.intelligence.urgency.sortPriority < rhs.intelligence.urgency.sortPriority
            }

            switch (lhs.draft.dueDate, rhs.draft.dueDate) {
            case (.some(let lhsDueDate), .some(let rhsDueDate)):
                return lhsDueDate < rhsDueDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.draft.source.receivedAt > rhs.draft.source.receivedAt
            }
        }
    }
}

import Foundation

public enum ManualDraftFactory {
    public static func makeDraft(
        id: UUID = UUID(),
        title: String,
        dueDate: Date?,
        amount: Decimal?,
        ownerID: UUID?,
        areaID: UUID?,
        recurrence: HouseholdRecurrence? = nil
    ) -> InboxDraft {
        InboxDraft.pending(
            id: id,
            source: SourceEmail(
                gmailMessageID: "manual-\(id.uuidString)",
                subject: title,
                from: "Manual entry",
                receivedAt: Date(),
                label: "Manual",
                bodyPreview: "Created in Household Command Center."
            ),
            title: title,
            dueDate: dueDate,
            amount: amount,
            ownerID: ownerID,
            areaID: areaID,
            extractionConfidence: 1,
            evidence: ["Manual household item"]
        ).withRecurrence(recurrence)
    }
}

private extension InboxDraft {
    func withRecurrence(_ recurrence: HouseholdRecurrence?) -> InboxDraft {
        var draft = self
        draft.recurrence = recurrence
        return draft
    }
}

public struct HouseholdDashboard: Equatable, Sendable {
    public var household: HouseholdContext
    public var drafts: [InboxDraft]
    public var now: Date

    public init(household: HouseholdContext, drafts: [InboxDraft], now: Date) {
        self.household = household
        self.drafts = drafts
        self.now = now
    }

    public var billsDueSoon: [InboxDraft] {
        drafts
            .filter { $0.amount != nil }
            .filter(isOpen)
            .filter { draft in
                guard let dueDate = draft.dueDate else { return false }
                return dueDate >= now && dueDate <= now.addingTimeInterval(7 * 86_400)
            }
            .sortedByDueDate()
    }

    public var weeklyReviewItems: [InboxDraft] {
        drafts
            .filter(isOpen)
            .filter { draft in
                draft.ownerID == nil
                    || draft.status == .calendarRetryRequired
                    || draft.status == .calendarUpdateRequired
                    || draft.status == .changedExternally
            }
            .sorted { left, right in
                reviewPriority(for: left) == reviewPriority(for: right)
                    ? (left.dueDate ?? .distantFuture) < (right.dueDate ?? .distantFuture)
                    : reviewPriority(for: left) < reviewPriority(for: right)
            }
    }

    public var areaSummaries: [HouseholdAreaSummary] {
        household.areas.map { area in
            let activeDrafts = drafts.filter { $0.areaID == area.id && isOpen($0) }
            let total = activeDrafts.reduce(Decimal(0)) { partialResult, draft in
                partialResult + (draft.amount ?? Decimal(0))
            }

            return HouseholdAreaSummary(
                areaID: area.id,
                areaName: area.name,
                defaultOwnerName: household.member(withID: area.defaultOwnerID)?.displayName,
                activeItemCount: activeDrafts.count,
                openObligationTotal: total
            )
        }
    }

    private func reviewPriority(for draft: InboxDraft) -> Int {
        switch draft.status {
        case .changedExternally:
            1
        case .calendarRetryRequired:
            2
        case .calendarUpdateRequired:
            2
        case .pendingApproval where draft.ownerID == nil:
            0
        case .pendingApproval:
            3
        case .approved, .rejected:
            4
        }
    }

    private func isOpen(_ draft: InboxDraft) -> Bool {
        draft.status != .approved
            && draft.status != .rejected
            && !(draft.triageState?.isClosed ?? false)
            && !DraftSnoozeService.isCurrentlySnoozed(draft, now: now)
    }
}

public struct HouseholdAreaSummary: Equatable, Sendable, Identifiable {
    public var id: UUID { areaID }
    public var areaID: UUID
    public var areaName: String
    public var defaultOwnerName: String?
    public var activeItemCount: Int
    public var openObligationTotal: Decimal

    public init(
        areaID: UUID,
        areaName: String,
        defaultOwnerName: String?,
        activeItemCount: Int,
        openObligationTotal: Decimal
    ) {
        self.areaID = areaID
        self.areaName = areaName
        self.defaultOwnerName = defaultOwnerName
        self.activeItemCount = activeItemCount
        self.openObligationTotal = openObligationTotal
    }

}

private extension Array where Element == InboxDraft {
    func sortedByDueDate() -> [InboxDraft] {
        sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}

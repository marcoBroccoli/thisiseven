import EvenCore
import Foundation

/// Placeholder rows for `.loading` skeletons — not preview fixtures.
/// Keeps production UI free of `PreviewData`.
enum InboxSkeletonData {
    private static let ownerId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static let drafts: [Draft] = [
        placeholderDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            from: "Sender one",
            subject: "Placeholder draft subject one",
            summary: "Summary line one"
        ),
        placeholderDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            from: "Sender two",
            subject: "Placeholder draft subject two",
            summary: "Summary line two"
        ),
    ]

    static let calendarItems: [CalendarItem] = [
        CalendarItem(
            kind: .task,
            id: "skeleton-task-1",
            title: "Placeholder calendar item",
            category: "chore",
            ownerMemberId: ownerId,
            amountCents: 1200,
            dueOn: "2026-08-08",
            done: false,
            googleEventUrl: "https://example.com"
        ),
        CalendarItem(
            kind: .draft,
            id: "skeleton-draft-1",
            title: "Another placeholder item",
            category: "bill",
            ownerMemberId: ownerId,
            amountCents: nil,
            dueOn: "2026-08-08",
            done: nil,
            googleEventUrl: nil
        ),
    ]

    private static func placeholderDraft(
        id: UUID,
        from: String,
        subject: String,
        summary: String
    ) -> Draft {
        Draft(
            id: id,
            fromLabel: from,
            subject: subject,
            summary: summary,
            urgency: 2,
            title: subject,
            ownerMemberId: ownerId,
            amountCents: nil,
            dueOn: "2026-08-08",
            reminder: .threeDays,
            status: .pending,
            createdByMemberId: ownerId
        )
    }
}

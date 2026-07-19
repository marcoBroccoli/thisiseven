import Foundation

public struct TodayReviewModel: Equatable, Sendable {
    public var drafts: [InboxDraft]
    public var household: HouseholdContext
    public var now: Date

    public init(drafts: [InboxDraft], household: HouseholdContext, now: Date = Date()) {
        self.drafts = drafts
        self.household = household
        self.now = now
    }

    public var sections: [TodayReviewSection] {
        let openDrafts = drafts.filter { draft in
            !((draft.triageState?.isClosed) ?? false)
                && draft.status != .approved
                && draft.status != .rejected
                && !DraftSnoozeService.isCurrentlySnoozed(draft, now: now)
        }
        let analyzer = EmailIntelligenceAnalyzer()
        var remainingIDs = Set(openDrafts.map(\.id))
        var sections: [TodayReviewSection] = []

        func appendSection(
            title: String,
            systemImage: String,
            matching predicate: (InboxDraft) -> Bool
        ) {
            let matches = openDrafts
                .filter { remainingIDs.contains($0.id) && predicate($0) }
                .sortedByTodayPriority(now: now)

            guard !matches.isEmpty else { return }
            matches.forEach { remainingIDs.remove($0.id) }
            sections.append(TodayReviewSection(title: title, systemImage: systemImage, drafts: matches))
        }

        appendSection(title: "Calendar Attention", systemImage: "calendar.badge.exclamationmark") {
            $0.status == .calendarRetryRequired
                || $0.status == .calendarUpdateRequired
                || $0.status == .changedExternally
        }
        appendSection(title: "Overdue", systemImage: "exclamationmark.triangle") {
            guard let dueDate = $0.dueDate else { return false }
            return dueDate < startOfToday
        }
        appendSection(title: "Due Today", systemImage: "calendar") {
            guard let dueDate = $0.dueDate else { return false }
            return dueDate >= startOfToday && dueDate < startOfTomorrow
        }
        appendSection(title: "Waiting", systemImage: "hourglass") {
            $0.triageState == .waiting
        }
        appendSection(title: "Needs Reply", systemImage: "arrowshape.turn.up.left") { draft in
            if let replyStatus = draft.replyStatus, replyStatus != .none {
                return replyStatus.requiresReplyAction
            }

            return analyzer.analyze(draft: draft, household: household, now: now).tags.contains(.replyNeeded)
        }

        return sections
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: now)
    }

    private var startOfTomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
    }
}

public struct TodayReviewSection: Equatable, Sendable, Identifiable {
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

private extension Array where Element == InboxDraft {
    func sortedByTodayPriority(now: Date) -> [InboxDraft] {
        sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case (.some(let lhsDueDate), .some(let rhsDueDate)):
                return lhsDueDate < rhsDueDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.source.receivedAt > rhs.source.receivedAt
            }
        }
    }
}

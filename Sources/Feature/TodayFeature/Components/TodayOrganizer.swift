import EvenCore
import Foundation

/// Display group for the Today list after client-side reorganize.
public struct TodayTaskGroup: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var tasks: [HouseholdTask]

    public init(id: String, label: String, tasks: [HouseholdTask]) {
        self.id = id
        self.label = label
        self.tasks = tasks
    }
}

/// Flat list rows so organize-mode changes keep stable task identities and
/// SwiftUI can move rows instead of fading whole sections in/out.
public enum TodayListRow: Equatable, Identifiable, Sendable {
    case header(id: String, label: String)
    case task(HouseholdTask)

    public var id: String {
        switch self {
        case let .header(id, _): "header-\(id)"
        case let .task(task): "task-\(task.id.uuidString)"
        }
    }
}

/// Regroups `/v1/summary` sections for Day / Type / Person organize modes.
public enum TodayOrganizer {
    public enum DayBucket: String, CaseIterable, Sendable {
        case overdue
        case today
        case tomorrow
        case later
        case noDate

        public var label: String {
            switch self {
            case .overdue: "OVERDUE"
            case .today: "TODAY"
            case .tomorrow: "TOMORROW"
            case .later: "LATER"
            case .noDate: "NO DATE"
            }
        }
    }

    public static func groups(
        summary: Summary,
        mode: TodayOrganizeMode,
        me: Member?,
        partner: Member?,
        now: Date = Date()
    ) -> [TodayTaskGroup] {
        switch mode {
        case .type:
            return typeGroups(summary: summary)
        case .day:
            return dayGroups(summary: summary, now: now)
        case .person:
            return personGroups(summary: summary, me: me, partner: partner)
        }
    }

    /// Header + task rows in one array — animate this value when organize mode flips.
    public static func rows(
        summary: Summary,
        mode: TodayOrganizeMode,
        me: Member?,
        partner: Member?,
        now: Date = Date()
    ) -> [TodayListRow] {
        groups(summary: summary, mode: mode, me: me, partner: partner, now: now)
            .flatMap { group -> [TodayListRow] in
                [.header(id: group.id, label: group.label)]
                    + group.tasks.map(TodayListRow.task)
            }
    }

    // MARK: - Type (API order)

    private static func typeGroups(summary: Summary) -> [TodayTaskGroup] {
        summary.sections.compactMap { section in
            guard !section.tasks.isEmpty else { return nil }
            return TodayTaskGroup(
                id: "type-\(section.key.rawValue)",
                label: section.label,
                tasks: section.tasks
            )
        }
    }

    // MARK: - Day

    private static func dayGroups(summary: Summary, now: Date) -> [TodayTaskGroup] {
        let calendar = Calendar.evenHousehold
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        var buckets: [DayBucket: [HouseholdTask]] = Dictionary(
            uniqueKeysWithValues: DayBucket.allCases.map { ($0, []) }
        )

        // Preserve summary order: chore section then admin, then task order.
        for task in summary.sections.flatMap(\.tasks) {
            let bucket = dayBucket(for: task.dueOn, today: today, tomorrow: tomorrow, calendar: calendar)
            buckets[bucket, default: []].append(task)
        }

        return DayBucket.allCases.compactMap { bucket in
            guard let tasks = buckets[bucket], !tasks.isEmpty else { return nil }
            return TodayTaskGroup(id: "day-\(bucket.rawValue)", label: bucket.label, tasks: tasks)
        }
    }

    public static func dayBucket(
        for dueOn: String?,
        today: Date,
        tomorrow: Date,
        calendar: Calendar = .evenHousehold
    ) -> DayBucket {
        guard let dueOn, let due = calendar.evenParseCivilDate(dueOn) else {
            return .noDate
        }
        let day = calendar.startOfDay(for: due)
        if day < today { return .overdue }
        if day == today { return .today }
        if day == tomorrow { return .tomorrow }
        return .later
    }

    // MARK: - Person

    private static func personGroups(
        summary: Summary,
        me: Member?,
        partner: Member?
    ) -> [TodayTaskGroup] {
        let orderedOwners: [(id: UUID?, label: String, key: String)] = [
            (me?.id, me?.displayName.uppercased() ?? "YOU", "me"),
            (partner?.id, partner?.displayName.uppercased() ?? "PARTNER", "partner"),
        ]

        var byOwner: [UUID: [HouseholdTask]] = [:]
        var unknown: [HouseholdTask] = []

        for task in summary.sections.flatMap(\.tasks) {
            if orderedOwners.contains(where: { $0.id == task.ownerMemberId }) {
                byOwner[task.ownerMemberId, default: []].append(task)
            } else {
                unknown.append(task)
            }
        }

        var groups: [TodayTaskGroup] = []
        for owner in orderedOwners {
            guard let id = owner.id, let tasks = byOwner[id], !tasks.isEmpty else { continue }
            groups.append(TodayTaskGroup(id: "person-\(owner.key)", label: owner.label, tasks: tasks))
        }
        if !unknown.isEmpty {
            groups.append(TodayTaskGroup(id: "person-unknown", label: "?", tasks: unknown))
        }
        return groups
    }
}

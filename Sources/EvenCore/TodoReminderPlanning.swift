import Foundation

/// A quiet on-device reminder for one calendar occurrence. Calendar item IDs
/// include the occurrence date for repeated todos, which keeps notification
/// requests stable without inventing a separate reminder database.
public struct TodoReminderPlan: Identifiable, Equatable, Sendable {
    public let calendarItemID: String
    public let occurrenceOn: String
    public let triggerDate: Date
    public let title: String
    public let body: String

    public var id: String { calendarItemID }

    public init(calendarItemID: String, occurrenceOn: String, triggerDate: Date,
                title: String, body: String) {
        self.calendarItemID = calendarItemID
        self.occurrenceOn = occurrenceOn
        self.triggerDate = triggerDate
        self.title = title
        self.body = body
    }
}

/// Creates one gentle, on-the-day alert at 09:00 for each upcoming calendar
/// occurrence. Google Calendar remains the shared source of truth; this is a
/// phone-local nudge for the person carrying the phone.
public enum TodoReminderPlanner {
    public static func plans(
        items: [CalendarItem],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        minimumLeadTime: TimeInterval = 60
    ) -> [TodoReminderPlan] {
        let today = calendar.startOfDay(for: now)

        return items.compactMap { item in
            guard item.kind == .task, item.done != true,
                  let occurrence = date(from: item.dueOn, calendar: calendar),
                  occurrence >= today,
                  let trigger = triggerDate(for: occurrence, calendar: calendar),
                  trigger.timeIntervalSince(now) >= minimumLeadTime
            else { return nil }

            return TodoReminderPlan(
                calendarItemID: item.id,
                occurrenceOn: item.dueOn,
                triggerDate: trigger,
                title: "Todo due today",
                body: "\(item.title) needs doing today."
            )
        }
        .sorted { left, right in
            if left.triggerDate == right.triggerDate { return left.id < right.id }
            return left.triggerDate < right.triggerDate
        }
    }

    private static func date(from day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func triggerDate(for occurrence: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: occurrence)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }
}

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

    public var id: String {
        calendarItemID
    }

    public init(calendarItemID: String, occurrenceOn: String, triggerDate: Date,
                title: String, body: String)
    {
        self.calendarItemID = calendarItemID
        self.occurrenceOn = occurrenceOn
        self.triggerDate = triggerDate
        self.title = title
        self.body = body
    }
}

/// Creates one gentle, on-the-day alert for each upcoming calendar occurrence:
/// at the todo's own hour when it has one, otherwise 09:00. Google Calendar
/// remains the shared source of truth; this is a phone-local nudge for the
/// person carrying the phone.
///
/// `/v1/calendar` items carry the occurrence date only — the hour lives on the
/// task — so a caller that knows the times passes them in keyed by task id
/// (the part of a calendar item id before the `:`).
public enum TodoReminderPlanner {
    public static func plans(
        items: [CalendarItem],
        dueTimes: [String: String] = [:],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        minimumLeadTime: TimeInterval = 60
    ) -> [TodoReminderPlan] {
        let today = calendar.startOfDay(for: now)

        return items.compactMap { item in
            let time = HouseholdTask.normalizedTimeOfDay(dueTimes[taskID(of: item)])
            guard item.kind == .task, item.done != true,
                  let occurrence = date(from: item.dueOn, calendar: calendar),
                  occurrence >= today,
                  let trigger = triggerDate(for: occurrence, at: time, calendar: calendar),
                  trigger.timeIntervalSince(now) >= minimumLeadTime
            else { return nil }

            return TodoReminderPlan(
                calendarItemID: item.id,
                occurrenceOn: item.dueOn,
                triggerDate: trigger,
                title: "Todo due today",
                body: time.map { "\(item.title) is due at \($0)." }
                    ?? "\(item.title) needs doing today."
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

    /// A repeat's calendar item id is `"{task_id}:{YYYY-MM-DD}"`; a one-off is
    /// the bare task id.
    private static func taskID(of item: CalendarItem) -> String {
        String(item.id.split(separator: ":").first ?? "")
    }

    private static func triggerDate(
        for occurrence: Date, at time: String?, calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: occurrence)
        let parts = (time ?? "09:00").split(separator: ":").compactMap { Int($0) }
        components.hour = parts.first ?? 9
        components.minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(from: components)
    }
}

import XCTest
@testable import EvenCore

final class TodoReminderPlanningTests: XCTestCase {
    private let owner = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testPlansTodayAtNineInTheDeviceCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 8))!

        let plans = TodoReminderPlanner.plans(items: [item(id: "dog-wash:2026-07-19", dueOn: "2026-07-19")],
                                              now: now, calendar: calendar)

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].id, "dog-wash:2026-07-19")
        XCTAssertEqual(plans[0].triggerDate,
                       calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 9)))
        XCTAssertEqual(plans[0].body, "Wash the dog needs doing today.")
    }

    func testSkipsCompletedPastAndAlreadyMissedOccurrences() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 10))!

        let plans = TodoReminderPlanner.plans(items: [
            item(id: "completed", dueOn: "2026-07-20", done: true),
            item(id: "past", dueOn: "2026-07-18"),
            item(id: "missed", dueOn: "2026-07-19"),
            item(id: "tomorrow", dueOn: "2026-07-20")
        ], now: now, calendar: calendar)

        XCTAssertEqual(plans.map(\.id), ["tomorrow"])
    }

    func testKeepsSeparateRecurringOccurrencesForTheSameTodo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 8))!

        let plans = TodoReminderPlanner.plans(items: [
            item(id: "dog-wash:2026-07-20", dueOn: "2026-07-20"),
            item(id: "dog-wash:2026-07-22", dueOn: "2026-07-22")
        ], now: now, calendar: calendar)

        XCTAssertEqual(plans.map(\.id), ["dog-wash:2026-07-20", "dog-wash:2026-07-22"])
    }

    private func item(id: String, dueOn: String, done: Bool? = nil) -> CalendarItem {
        CalendarItem(kind: .task, id: id, title: "Wash the dog", category: nil,
                     ownerMemberId: owner, amountCents: nil, dueOn: dueOn,
                     done: done, googleEventUrl: nil)
    }
}

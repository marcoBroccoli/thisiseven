@testable import EvenCore
import XCTest

final class ModelsTests: XCTestCase {
    func testSummaryDecodesFromSnakeCase() throws {
        let json = """
        {"week":{"id":"11111111-1111-1111-1111-111111111111","index":1,"started_on":"2026-07-13"},
         "pebbles":[{"member_id":"22222222-2222-2222-2222-222222222222","weight":3}],
         "percent_me":100,"percent_partner":0,
         "caption":"Empty pans. A new week, level by definition",
         "sections":[{"key":"chore","label":"CHORES — TODAY","tasks":[]}],
         "pending_draft_count":2}
        """.data(using: .utf8)!
        let summary = try EvenAPIClient.decoder.decode(Summary.self, from: json)
        XCTAssertEqual(summary.percentMe, 100)
        XCTAssertEqual(summary.pebbles.first?.weight, 3)
        XCTAssertEqual(summary.sections.first?.key, .chore)
        XCTAssertEqual(summary.pendingDraftCount, 2)
    }

    func testRecurrenceRawValues() {
        XCTAssertEqual(Recurrence.every2Days.rawValue, "every_2_days")
        XCTAssertEqual(DraftReminder.threeDays.rawValue, "3_days")
        XCTAssertEqual(DraftReplyStatus.openedInGmail.rawValue, "opened_in_gmail")
        XCTAssertEqual(DraftReplyStatus.sentManually.label, "Sent")
    }

    func testCalendarOccurrenceUsesStringIdentity() throws {
        let json = """
        {"kind":"task","id":"11111111-1111-1111-1111-111111111111:2026-07-22",
         "title":"Wash the dog","owner_member_id":"22222222-2222-2222-2222-222222222222",
         "due_on":"2026-07-22"}
        """.data(using: .utf8)!
        let item = try EvenAPIClient.decoder.decode(CalendarItem.self, from: json)
        XCTAssertEqual(item.id, "11111111-1111-1111-1111-111111111111:2026-07-22")
    }

    func testTaskUpdateEncodesAnExplicitDueDateClear() throws {
        let body = try EvenAPIClient.TaskDraftBody(
            title: "Wash the dog", section: .chore,
            ownerMemberId: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            weight: 1, recurrence: .weekly, clearDueOn: true
        )

        let json = try JSONSerialization.jsonObject(with: EvenAPIClient.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(json?["clear_due_on"] as? Bool, true)
    }

    func testCalendarResolutionActionUsesWireValues() throws {
        let body = EvenAPIClient.CalendarResolutionBody(action: .restore)

        let json = try JSONSerialization.jsonObject(with: EvenAPIClient.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(json?["action"] as? String, "restore")
        XCTAssertTrue(CalendarSyncState.externalDeleted.requiresResolution)
        XCTAssertFalse(CalendarSyncState.synced.requiresResolution)
    }

    /// Mirrors `metaLine` in `backend/internal/api/types.go`.
    func testTaskMetaLineMirrorsBackend() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))

        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-07", recurrence: .none, now: now, calendar: calendar),
            "TODAY"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-08", recurrence: .none, now: now, calendar: calendar),
            "TOMORROW"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-06", recurrence: .none, now: now, calendar: calendar),
            "1 DAY OVER"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-04", recurrence: .none, now: now, calendar: calendar),
            "3 DAYS OVER"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-12", recurrence: .weekly, now: now, calendar: calendar),
            "AUG 12 · WEEKLY"
        )
        // Daily / every-2-days omit the due phrase (backend skips it).
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-07", recurrence: .daily, now: now, calendar: calendar),
            "DAILY"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-07", recurrence: .every2Days, now: now, calendar: calendar),
            "EVERY 2 DAYS"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                originLabel: "Vattenfall",
                dueOn: "2026-08-08",
                recurrence: .weekly,
                now: now,
                calendar: calendar
            ),
            "VATTENFALL · TOMORROW · WEEKLY"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: "2026-08-08", recurrence: .weekly, now: now, calendar: calendar),
            "TOMORROW · WEEKLY"
        )
        // No date + weekly → frequency only (the createSucceeded regression shape).
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: nil, recurrence: .weekly, now: now, calendar: calendar),
            "WEEKLY"
        )
        // No date + one-off → empty (not a hardcoded "TODAY").
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: nil, recurrence: .none, now: now, calendar: calendar),
            ""
        )
    }

    func testResolvedMetaLineRecomputesFromDueOn() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        // Stale stored meta after a bad create response — structured fields win.
        let task = HouseholdTask(
            id: UUID(),
            title: "Pay insurance",
            section: .admin,
            ownerMemberId: PreviewData.ada.id,
            weight: 2,
            recurrence: .weekly,
            dueOn: "2026-08-08",
            done: false,
            metaLine: "WEEKLY"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                originLabel: HouseholdTask.originLabel(fromMetaLine: task.metaLine),
                dueOn: task.dueOn,
                recurrence: task.recurrence,
                now: now,
                calendar: calendar
            ),
            "TOMORROW · WEEKLY"
        )
        XCTAssertEqual(HouseholdTask.originLabel(fromMetaLine: "WEEKLY"), nil)
        XCTAssertEqual(HouseholdTask.originLabel(fromMetaLine: "TOMORROW · WEEKLY"), nil)
        XCTAssertEqual(
            HouseholdTask.originLabel(fromMetaLine: "VATTENFALL · TOMORROW · WEEKLY"),
            "VATTENFALL"
        )
        XCTAssertEqual(HouseholdTask.originLabel(fromMetaLine: "AUG 12 · WEEKLY"), nil)
    }

    /// A repeat is a rule anchored on its due date, so the row must describe the
    /// **next** occurrence. Describing the anchor makes a healthy weekly chore
    /// read "21 DAYS OVER · WEEKLY".
    func testWeeklyMetaLineDescribesNextOccurrenceNotAnchor() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))

        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-07-17", recurrence: .weekly, now: now, calendar: calendar
            ),
            "TODAY · WEEKLY"
        )
        // Anchored yesterday: the next hit is six days out.
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-06", recurrence: .weekly, now: now, calendar: calendar
            ),
            "AUG 13 · WEEKLY"
        )
    }

    func testMetaLineAppendsTheRecurrenceEnd() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))

        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-08", recurrence: .weekly,
                recurrenceUntil: "2026-09-12", now: now, calendar: calendar
            ),
            "TOMORROW · WEEKLY · UNTIL SEP 12"
        )
        // A count echoes how the household expressed the bound.
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-08", recurrence: .weekly,
                recurrenceUntil: "2026-09-12", recurrenceCount: 6, now: now, calendar: calendar
            ),
            "TOMORROW · WEEKLY · 6 TIMES"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-07", recurrence: .daily,
                recurrenceCount: 10, now: now, calendar: calendar
            ),
            "DAILY · 10 TIMES"
        )
        // A one-off has no series to bound.
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-08", recurrence: .none,
                recurrenceUntil: "2026-09-12", now: now, calendar: calendar
            ),
            "TOMORROW"
        )
    }

    func testMetaLineDropsTheDueTipOnceTheSeriesIsOver() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))

        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-07-17", recurrence: .weekly,
                recurrenceUntil: "2026-07-31", now: now, calendar: calendar
            ),
            "WEEKLY · UNTIL JUL 31"
        )
    }

    func testRecurrenceEndTurnsACountIntoADate() throws {
        let calendar = Calendar.evenHousehold
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))

        // Six weekly occurrences span five intervals from the anchor.
        XCTAssertEqual(
            Recurrence.weekly.recurrenceEnd(anchor: anchor, count: 6)
                .map(calendar.evenCivilDateString(from:)),
            "2026-08-24"
        )
        XCTAssertEqual(
            Recurrence.every2Days.recurrenceEnd(anchor: anchor, count: 6)
                .map(calendar.evenCivilDateString(from:)),
            "2026-07-30"
        )
        XCTAssertEqual(
            Recurrence.daily.recurrenceEnd(anchor: anchor, count: 1)
                .map(calendar.evenCivilDateString(from:)),
            "2026-07-20"
        )
        XCTAssertNil(Recurrence.weekly.recurrenceEnd(anchor: anchor))
        XCTAssertNil(Recurrence.none.recurrenceEnd(anchor: anchor, count: 6))
    }

    func testNextOccurrenceStepsForwardAndRunsOut() {
        let calendar = Calendar.evenHousehold
        let day = { (d: Int) in calendar.date(from: DateComponents(year: 2026, month: 7, day: d))! }

        XCTAssertEqual(
            Recurrence.weekly.nextOccurrence(anchor: day(20), from: day(20)), day(20)
        )
        XCTAssertEqual(
            Recurrence.weekly.nextOccurrence(anchor: day(20), from: day(21)), day(27)
        )
        // The last scheduled day is still reachable.
        XCTAssertEqual(
            Recurrence.weekly.nextOccurrence(anchor: day(20), until: day(27), from: day(27)),
            day(27)
        )
        XCTAssertNil(
            Recurrence.weekly.nextOccurrence(anchor: day(20), until: day(27), from: day(28))
        )
        XCTAssertNil(Recurrence.none.nextOccurrence(anchor: day(20), from: day(20)))
    }

    func testTaskCreateEncodesTheRecurrenceEnd() throws {
        let body = EvenAPIClient.TaskDraftBody(
            title: "Water the plants", section: .chore,
            ownerMemberId: PreviewData.ada.id,
            weight: 1, recurrence: .weekly, dueOn: "2026-08-08",
            recurrenceCount: 6
        )

        let json = try JSONSerialization.jsonObject(
            with: EvenAPIClient.encoder.encode(body)
        ) as? [String: Any]
        XCTAssertEqual(json?["recurrence_count"] as? Int, 6)
        XCTAssertNil(json?["recurrence_until"])
        XCTAssertEqual(json?["clear_recurrence_end"] as? Bool, false)
    }

    /// A todo that says *when*: the hour rides just after the day it belongs to,
    /// and daily repeats — which print no day — still show it.
    func testMetaLineCarriesTheTimeOfDay() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))

        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-08", dueTime: "14:00", recurrence: .none,
                now: now, calendar: calendar
            ),
            "TOMORROW · 14:00"
        )
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-07", dueTime: "18:30", recurrence: .daily,
                now: now, calendar: calendar
            ),
            "18:30 · DAILY"
        )
        // All day is every todo without one — nothing extra on the row.
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: "2026-08-08", recurrence: .none, now: now, calendar: calendar
            ),
            "TOMORROW"
        )
        // The hour hangs off the date: no day, nothing to say.
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(
                dueOn: nil, dueTime: "14:00", recurrence: .none, now: now, calendar: calendar
            ),
            ""
        )
        // Postgres spells a `time` with seconds; a half-typed one is dropped.
        XCTAssertEqual(HouseholdTask.normalizedTimeOfDay("09:05:00"), "09:05")
        XCTAssertEqual(HouseholdTask.normalizedTimeOfDay("9:5"), "09:05")
        XCTAssertNil(HouseholdTask.normalizedTimeOfDay("24:00"))
        XCTAssertNil(HouseholdTask.normalizedTimeOfDay("noon"))
        XCTAssertNil(HouseholdTask.normalizedTimeOfDay(nil))
        // A leading hour is the todo's time, never a Gmail origin label.
        XCTAssertNil(HouseholdTask.originLabel(fromMetaLine: "14:00 · DAILY"))
    }

    func testTaskCarriesTheTimeOfDayOverTheWire() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","title":"Pick up the parcel",
         "section":"chore","owner_member_id":"22222222-2222-2222-2222-222222222222",
         "weight":1,"recurrence":"none","due_on":"2026-08-08","due_time":"14:00",
         "done":false,"meta_line":"TOMORROW","calendar_sync_state":"synced"}
        """.data(using: .utf8)!

        let task = try EvenAPIClient.decoder.decode(HouseholdTask.self, from: json)
        XCTAssertEqual(task.dueTime, "14:00")

        // An all-day todo — every todo that existed before the field — decodes
        // with no time rather than failing.
        let allDay = try EvenAPIClient.decoder.decode(
            HouseholdTask.self,
            from: Data(String(data: json, encoding: .utf8)!
                .replacingOccurrences(of: "\"due_time\":\"14:00\",", with: "").utf8)
        )
        XCTAssertNil(allDay.dueTime)

        let body = EvenAPIClient.TaskDraftBody(
            title: task.title, section: .chore, ownerMemberId: task.ownerMemberId,
            weight: 1, recurrence: .none, dueOn: "2026-08-08", dueTime: "14:00"
        )
        let encoded = try JSONSerialization.jsonObject(
            with: EvenAPIClient.encoder.encode(body)
        ) as? [String: Any]
        XCTAssertEqual(encoded?["due_time"] as? String, "14:00")
        XCTAssertEqual(encoded?["clear_due_time"] as? Bool, false)

        // Back to all day: the flag has to say so out loud, and never alongside
        // a time — the API answers `400 bad_time` to both together.
        let clearing = EvenAPIClient.TaskDraftBody(
            title: task.title, section: .chore, ownerMemberId: task.ownerMemberId,
            weight: 1, recurrence: .none, dueOn: "2026-08-08", clearDueTime: true
        )
        let clearingJSON = try JSONSerialization.jsonObject(
            with: EvenAPIClient.encoder.encode(clearing)
        ) as? [String: Any]
        XCTAssertNil(clearingJSON?["due_time"])
        XCTAssertEqual(clearingJSON?["clear_due_time"] as? Bool, true)
    }

    func testTaskDecodesTheRecurrenceEnd() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","title":"Water the plants",
         "section":"chore","owner_member_id":"22222222-2222-2222-2222-222222222222",
         "weight":1,"recurrence":"weekly","due_on":"2026-08-08",
         "recurrence_until":"2026-09-12","recurrence_count":6,
         "done":false,"meta_line":"TOMORROW · WEEKLY · 6 TIMES",
         "calendar_sync_state":"not_scheduled"}
        """.data(using: .utf8)!

        let task = try EvenAPIClient.decoder.decode(HouseholdTask.self, from: json)
        XCTAssertEqual(task.recurrenceUntil, "2026-09-12")
        XCTAssertEqual(task.recurrenceCount, 6)
    }

    /// `ISO8601DateFormatter` defaults to GMT: Amsterdam midnight of Aug 8 is
    /// still Aug 7 UTC, so a naïve full-date format would emit `"2026-08-07"`
    /// and `makeMetaLine` would label tomorrow as TODAY.
    func testCivilDueDateAvoidsGMTOffByOne() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 15)))
        let tomorrowStart = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        ))

        let gmtTrap = ISO8601DateFormatter()
        gmtTrap.formatOptions = [.withFullDate]
        XCTAssertEqual(gmtTrap.string(from: tomorrowStart), "2026-08-07")

        let dueOn = calendar.evenCivilDateString(from: tomorrowStart)
        XCTAssertEqual(dueOn, "2026-08-08")
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: dueOn, recurrence: .none, now: now),
            "TOMORROW"
        )
    }
}

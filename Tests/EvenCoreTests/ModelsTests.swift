import XCTest
@testable import EvenCore

final class ModelsTests: XCTestCase {
    func testSummaryDecodesFromSnakeCase() throws {
        let json = """
        {"week":{"id":"11111111-1111-1111-1111-111111111111","index":1,"started_on":"2026-07-13"},
         "pebbles":[{"member_id":"22222222-2222-2222-2222-222222222222","weight":3}],
         "percent_me":100,"percent_partner":0,
         "caption":"Empty pans. A new week, level by definition.",
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
        let body = EvenAPIClient.TaskDraftBody(
            title: "Wash the dog", section: .chore,
            ownerMemberId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            weight: 1, recurrence: .weekly, clearDueOn: true)

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
}

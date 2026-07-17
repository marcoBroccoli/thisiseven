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
    }
}

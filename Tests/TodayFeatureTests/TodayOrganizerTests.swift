import EvenCore
import Foundation
import TodayFeature
import XCTest

final class TodayOrganizerTests: XCTestCase {
    private let calendar = Calendar.evenHousehold

    private var today: Date {
        calendar.evenParseCivilDate("2026-08-07")!
    }

    private var tomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
    }

    func testDayBucketClassification() {
        let start = calendar.startOfDay(for: today)
        XCTAssertEqual(
            TodayOrganizer.dayBucket(for: nil, today: start, tomorrow: tomorrow),
            .noDate
        )
        XCTAssertEqual(
            TodayOrganizer.dayBucket(for: "2026-08-05", today: start, tomorrow: tomorrow),
            .overdue
        )
        XCTAssertEqual(
            TodayOrganizer.dayBucket(for: "2026-08-07", today: start, tomorrow: tomorrow),
            .today
        )
        XCTAssertEqual(
            TodayOrganizer.dayBucket(for: "2026-08-08", today: start, tomorrow: tomorrow),
            .tomorrow
        )
        XCTAssertEqual(
            TodayOrganizer.dayBucket(for: "2026-08-12", today: start, tomorrow: tomorrow),
            .later
        )
    }

    func testDayGroupsOmitEmptyBucketsAndPreserveOrder() {
        let groups = TodayOrganizer.groups(
            summary: PreviewData.summary,
            mode: .day,
            me: PreviewData.ada,
            partner: PreviewData.umut,
            now: today
        )
        XCTAssertEqual(
            groups.map(\.id),
            ["day-overdue", "day-today", "day-tomorrow", "day-later", "day-noDate"]
        )
        XCTAssertEqual(groups.map(\.label), ["OVERDUE", "TODAY", "TOMORROW", "LATER", "NO DATE"])

        // Chore-then-admin order within OVERDUE: waterBill (admin) after insurance only
        // if insurance appears first in flatMap — chores section first, so vacuum isn't overdue.
        let overdueIds = groups[0].tasks.map(\.id)
        XCTAssertTrue(overdueIds.contains(PreviewData.waterBill.id))
        XCTAssertTrue(overdueIds.contains(PreviewData.insurance.id))
        XCTAssertEqual(overdueIds.first, PreviewData.waterBill.id)

        XCTAssertEqual(
            groups.first(where: { $0.id == "day-today" })?.tasks.map(\.id),
            [PreviewData.laundry.id, PreviewData.trash.id]
        )
        XCTAssertEqual(
            groups.first(where: { $0.id == "day-tomorrow" })?.tasks.map(\.id),
            [PreviewData.dishes.id]
        )
        XCTAssertEqual(
            groups.first(where: { $0.id == "day-later" })?.tasks.map(\.id),
            [PreviewData.vacuum.id]
        )
        XCTAssertEqual(
            groups.first(where: { $0.id == "day-noDate" })?.tasks.map(\.id),
            [PreviewData.groceries.id]
        )
    }

    func testTypeGroupsPassthroughNonEmptySections() {
        let groups = TodayOrganizer.groups(
            summary: PreviewData.summary,
            mode: .type,
            me: PreviewData.ada,
            partner: PreviewData.umut,
            now: today
        )
        XCTAssertEqual(groups.map(\.label), ["CHORES", "ADMIN"])
        XCTAssertEqual(
            groups[0].tasks.map(\.id),
            [
                PreviewData.laundry.id,
                PreviewData.dishes.id,
                PreviewData.trash.id,
                PreviewData.groceries.id,
                PreviewData.vacuum.id,
            ]
        )
        XCTAssertEqual(
            groups[1].tasks.map(\.id),
            [PreviewData.waterBill.id, PreviewData.insurance.id]
        )
    }

    func testPersonGroupsSplitByOwner() {
        let groups = TodayOrganizer.groups(
            summary: PreviewData.summary,
            mode: .person,
            me: PreviewData.ada,
            partner: PreviewData.umut,
            now: today
        )
        XCTAssertEqual(groups.map(\.id), ["person-me", "person-partner"])
        XCTAssertEqual(groups.map(\.label), ["ADA", "UMUT"])
        XCTAssertEqual(
            Set(groups[0].tasks.map(\.id)),
            [PreviewData.laundry.id, PreviewData.trash.id, PreviewData.groceries.id]
        )
        XCTAssertEqual(
            Set(groups[1].tasks.map(\.id)),
            [
                PreviewData.dishes.id,
                PreviewData.vacuum.id,
                PreviewData.waterBill.id,
                PreviewData.insurance.id,
            ]
        )
    }

    func testRowsKeepStableTaskIdentitiesAcrossModes() {
        let day = TodayOrganizer.rows(
            summary: PreviewData.summary,
            mode: .day,
            me: PreviewData.ada,
            partner: PreviewData.umut,
            now: today
        )
        let type = TodayOrganizer.rows(
            summary: PreviewData.summary,
            mode: .type,
            me: PreviewData.ada,
            partner: PreviewData.umut,
            now: today
        )
        let dayTaskIds = day.compactMap { row -> String? in
            if case .task = row { return row.id }
            return nil
        }
        let typeTaskIds = type.compactMap { row -> String? in
            if case .task = row { return row.id }
            return nil
        }
        XCTAssertEqual(Set(dayTaskIds), Set(typeTaskIds))
        XCTAssertEqual(dayTaskIds.count, PreviewData.summary.sections.flatMap(\.tasks).count)
        XCTAssertTrue(day.contains { $0.id.hasPrefix("header-") })
    }

    func testPreviewPebblesMatchDoneTaskWeights() {
        let done = PreviewData.summary.sections.flatMap(\.tasks).filter(\.done)
        let expected = done.map { Pebble(memberId: $0.ownerMemberId, weight: $0.weight) }
        // Same multiset of (owner, weight) — order is fixture order of completions.
        XCTAssertEqual(PreviewData.summary.pebbles, expected)
        XCTAssertEqual(done.map(\.weight).reduce(0, +), 9)
        XCTAssertTrue(done.allSatisfy { (1 ... 3).contains($0.weight) })
        XCTAssertEqual(PreviewData.summary.percentMe, 57)
        XCTAssertEqual(PreviewData.summary.percentPartner, 43)
    }
}

import XCTest
@testable import HouseholdCore

final class IntakeWorkflowTests: XCTestCase {
    func testImportUsesHouseholdTodoLabelAndCreatesDraftsFromExtraction() async {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let area = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Utilities", defaultOwnerID: owner.id)
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [owner],
            areas: [area],
            sharedCalendarID: "household@example.com"
        )
        let gmail = RecordingGmailClient(messages: [
            SourceEmail(
                gmailMessageID: "msg-bill",
                subject: "Water bill",
                from: "water@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Due next Wednesday."
            )
        ])
        let extractor = StaticEmailExtractor(result: ExtractionResult(
            title: "Pay water bill",
            dueDate: Date(timeIntervalSince1970: 1_800_259_200),
            amount: Decimal(42.50),
            suggestedOwnerID: nil,
            areaID: area.id,
            evidence: ["Due next Wednesday."],
            confidence: 0.88
        ))
        let service = HouseholdInboxImportService(gmail: gmail, extractor: extractor)

        let drafts = await service.importDrafts(in: household)

        XCTAssertEqual(gmail.requestedLabels, ["HouseholdTodo"])
        XCTAssertEqual(extractor.extractedMessageIDs, ["msg-bill"])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].title, "Pay water bill")
        XCTAssertEqual(drafts[0].ownerID, owner.id)
        XCTAssertEqual(drafts[0].status, .pendingApproval)
    }

    func testLowConfidenceExtractionLeavesActionFieldsBlank() {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let area = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Utilities", defaultOwnerID: owner.id)
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [owner],
            areas: [area],
            sharedCalendarID: "household@example.com"
        )
        let email = SourceEmail(
            gmailMessageID: "msg-uncertain",
            subject: "Long confusing thread",
            from: "sender@example.com",
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
            label: "HouseholdTodo",
            bodyPreview: "Maybe next week, maybe later."
        )
        let extraction = ExtractionResult(
            title: "Maybe pay something",
            dueDate: Date(timeIntervalSince1970: 1_800_259_200),
            amount: Decimal(42.50),
            suggestedOwnerID: owner.id,
            areaID: area.id,
            evidence: ["Maybe next week, maybe later."],
            confidence: 0.41
        )

        let draft = DraftFactory.makeDraft(from: email, extraction: extraction, household: household)

        XCTAssertEqual(draft.title, "Maybe pay something")
        XCTAssertNil(draft.dueDate)
        XCTAssertNil(draft.amount)
        XCTAssertNil(draft.ownerID)
        XCTAssertNil(draft.areaID)
        XCTAssertEqual(draft.extractionConfidence, 0.41)
    }

    func testThrowingImportReportsGmailFailures() async {
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [],
            areas: [],
            sharedCalendarID: nil
        )
        let service = HouseholdInboxImportService(
            gmail: FailingGmailClient(error: TestIntakeError.gmailUnavailable),
            extractor: StaticEmailExtractor(result: ExtractionResult(
                title: "unused",
                dueDate: nil,
                amount: nil,
                suggestedOwnerID: nil,
                areaID: nil,
                evidence: [],
                confidence: 0
            ))
        )

        do {
            _ = try await service.importDraftsThrowing(in: household)
            XCTFail("Expected Gmail failure to be thrown.")
        } catch TestIntakeError.gmailUnavailable {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHeuristicExtractorOrganizesBillsIntoAreasAmountsAndDueDates() async throws {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let utilities = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Utilities", defaultOwnerID: owner.id)
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [owner],
            areas: [utilities],
            sharedCalendarID: nil
        )
        let email = SourceEmail(
            gmailMessageID: "msg-energy",
            subject: "Electricity bill due tomorrow",
            from: "billing@energy.example",
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
            label: "Auto Household",
            bodyPreview: "Your electricity bill of 84.25 is due tomorrow."
        )
        let extractor = HouseholdHeuristicEmailExtractor(now: Date(timeIntervalSince1970: 1_800_000_000))

        let result = try await extractor.extract(from: email, household: household)

        XCTAssertEqual(result.title, "Electricity bill due tomorrow")
        XCTAssertEqual(result.amount, Decimal(string: "84.25"))
        XCTAssertEqual(
            result.dueDate,
            Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: 1_800_086_400))
        )
        XCTAssertEqual(result.areaID, utilities.id)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.60)
    }

    func testHeuristicExtractorRecognizesNextWeekdayDates() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6, hour: 9))!
        let email = SourceEmail(
            gmailMessageID: "msg-next-wednesday",
            subject: "Water bill due next Wednesday",
            from: "billing@water.example",
            receivedAt: now,
            label: "Auto Household",
            bodyPreview: "Please pay EUR 42.50 due next Wednesday."
        )
        let extractor = HouseholdHeuristicEmailExtractor(now: now, calendar: calendar)

        let result = try await extractor.extract(
            from: email,
            household: HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil)
        )

        XCTAssertEqual(result.dueDate, calendar.date(from: DateComponents(year: 2026, month: 1, day: 14))!)
        XCTAssertEqual(result.amount, Decimal(string: "42.50"))
    }

    func testHeuristicExtractorRecognizesAbsoluteAndRelativeDates() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 9))!
        let household = HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil)
        let extractor = HouseholdHeuristicEmailExtractor(now: now, calendar: calendar)

        let absolute = try await extractor.extract(
            from: SourceEmail(
                gmailMessageID: "msg-absolute-date",
                subject: "Insurance payment due 16/07",
                from: "insurer@example.com",
                receivedAt: now,
                label: "Auto Household",
                bodyPreview: "Your payment is due 16/07."
            ),
            household: household
        )
        let relative = try await extractor.extract(
            from: SourceEmail(
                gmailMessageID: "msg-relative-date",
                subject: "Appointment confirmation",
                from: "clinic@example.com",
                receivedAt: now,
                label: "Auto Household",
                bodyPreview: "Your appointment is in 3 days."
            ),
            household: household
        )

        XCTAssertEqual(absolute.dueDate, calendar.date(from: DateComponents(year: 2026, month: 7, day: 16))!)
        XCTAssertEqual(relative.dueDate, calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!)
    }
}

private final class RecordingGmailClient: GmailClient, @unchecked Sendable {
    var requestedLabels: [String] = []
    private let messages: [SourceEmail]

    init(messages: [SourceEmail]) {
        self.messages = messages
    }

    func messages(labeled label: String) async throws -> [SourceEmail] {
        requestedLabels.append(label)
        return messages
    }
}

private final class StaticEmailExtractor: EmailExtractor, @unchecked Sendable {
    var extractedMessageIDs: [String] = []
    private let result: ExtractionResult

    init(result: ExtractionResult) {
        self.result = result
    }

    func extract(from email: SourceEmail, household: HouseholdContext) async throws -> ExtractionResult {
        extractedMessageIDs.append(email.gmailMessageID)
        return result
    }
}

private struct FailingGmailClient: GmailClient {
    var error: Error

    func messages(labeled label: String) async throws -> [SourceEmail] {
        throw error
    }
}

private enum TestIntakeError: Error {
    case gmailUnavailable
}

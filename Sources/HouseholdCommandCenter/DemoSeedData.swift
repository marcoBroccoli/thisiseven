import Foundation
import HouseholdCore

enum DemoSeedData {
    static func make() -> Seed {
        let now = Date()
        let marco = HouseholdMember(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Marco",
            email: "marco@example.com"
        )
        let partner = HouseholdMember(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Partner",
            email: "partner@example.com"
        )
        let utilities = HouseholdArea(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Utilities",
            defaultOwnerID: marco.id
        )
        let subscriptions = HouseholdArea(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "Subscriptions",
            defaultOwnerID: partner.id
        )
        let admin = HouseholdArea(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            name: "Admin",
            defaultOwnerID: marco.id
        )
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [marco, partner],
            areas: [utilities, subscriptions, admin],
            sharedCalendarID: "family-calendar@example.com"
        )

        let water = SourceEmail(
            gmailMessageID: "gmail-water",
            subject: "Water bill due next Wednesday",
            from: "billing@water.example",
            receivedAt: now.addingTimeInterval(-3_600),
            label: "HouseholdTodo",
            bodyPreview: "Your water bill of 42.50 is due next Wednesday."
        )
        let insurance = SourceEmail(
            gmailMessageID: "gmail-insurance",
            subject: "Insurance renewal reminder",
            from: "renewals@insurance.example",
            receivedAt: now.addingTimeInterval(-7_200),
            label: "HouseholdTodo",
            bodyPreview: "Renew your household insurance before Monday. Amount: 129.99."
        )
        let school = SourceEmail(
            gmailMessageID: "gmail-school",
            subject: "School form follow up",
            from: "school@example.edu",
            receivedAt: now.addingTimeInterval(-10_800),
            label: "HouseholdTodo",
            bodyPreview: "Please review the attached form when you can."
        )

        let extractions = [
            water.gmailMessageID: ExtractionResult(
                title: "Pay water bill",
                dueDate: now.addingTimeInterval(2 * 86_400),
                amount: Decimal(42.50),
                suggestedOwnerID: nil,
                areaID: utilities.id,
                evidence: ["water bill of 42.50", "due next Wednesday"],
                confidence: 0.88
            ),
            insurance.gmailMessageID: ExtractionResult(
                title: "Renew household insurance",
                dueDate: now.addingTimeInterval(5 * 86_400),
                amount: Decimal(129.99),
                suggestedOwnerID: partner.id,
                areaID: subscriptions.id,
                evidence: ["Renew before Monday", "Amount: 129.99"],
                confidence: 0.92
            ),
            school.gmailMessageID: ExtractionResult(
                title: "Review school form",
                dueDate: nil,
                amount: nil,
                suggestedOwnerID: nil,
                areaID: admin.id,
                evidence: ["review the attached form"],
                confidence: 0.48
            )
        ]

        var initialDrafts = [water, insurance, school].compactMap { email in
            extractions[email.gmailMessageID].map {
                DraftFactory.makeDraft(from: email, extraction: $0, household: household)
            }
        }

        var retry = ManualDraftFactory.makeDraft(
            title: "Retry calendar write for cleaner deposit",
            dueDate: now.addingTimeInterval(4 * 86_400),
            amount: Decimal(60),
            ownerID: marco.id,
            areaID: admin.id
        )
        retry.status = .calendarRetryRequired
        retry.lastError = "Demo retry state: Calendar token expired."
        initialDrafts.append(retry)

        var external = ManualDraftFactory.makeDraft(
            title: "Confirm changed dentist appointment",
            dueDate: now.addingTimeInterval(6 * 86_400),
            amount: nil,
            ownerID: partner.id,
            areaID: admin.id
        )
        external.status = .changedExternally
        external.googleEventID = "demo-external-change"
        external.lastError = "Demo external change: Google Calendar event was edited outside the app."
        initialDrafts.append(external)

        return Seed(household: household, emails: [water, insurance, school], extractions: extractions, initialDrafts: initialDrafts)
    }
}

struct Seed {
    var household: HouseholdContext
    var emails: [SourceEmail]
    var extractions: [String: ExtractionResult]
    var initialDrafts: [InboxDraft]
}

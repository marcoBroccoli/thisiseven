import Foundation

public enum DraftFactory {
    public static let minimumActionConfidence = 0.60

    public static func makeDraft(from email: SourceEmail, extraction: ExtractionResult, household: HouseholdContext) -> InboxDraft {
        let isActionable = extraction.confidence >= minimumActionConfidence
        let areaID = isActionable ? extraction.areaID : nil
        let ownerID = isActionable ? extraction.suggestedOwnerID ?? household.area(withID: areaID)?.defaultOwnerID : nil
        let title = extraction.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        return InboxDraft.pending(
            source: email,
            title: title?.isEmpty == false ? title! : email.subject,
            dueDate: isActionable ? extraction.dueDate : nil,
            amount: isActionable ? extraction.amount : nil,
            ownerID: ownerID,
            areaID: areaID,
            extractionConfidence: extraction.confidence,
            evidence: extraction.evidence
        )
    }
}

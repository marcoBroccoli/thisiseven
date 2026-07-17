import Foundation

public protocol GmailClient: Sendable {
    func messages(labeled label: String) async throws -> [SourceEmail]
}

public protocol EmailExtractor: Sendable {
    func extract(from email: SourceEmail, household: HouseholdContext) async throws -> ExtractionResult
}

public final class HouseholdInboxImportService: Sendable {
    private let gmail: GmailClient
    private let extractor: EmailExtractor
    private let label: String

    public init(gmail: GmailClient, extractor: EmailExtractor, label: String = "HouseholdTodo") {
        self.gmail = gmail
        self.extractor = extractor
        self.label = label
    }

    public func importDrafts(in household: HouseholdContext) async -> [InboxDraft] {
        do {
            return try await importDraftsThrowing(in: household)
        } catch {
            return []
        }
    }

    public func importDraftsThrowing(in household: HouseholdContext) async throws -> [InboxDraft] {
        let messages = try await gmail.messages(labeled: label)
        var drafts: [InboxDraft] = []

        for message in messages {
            do {
                let extraction = try await extractor.extract(from: message, household: household)
                drafts.append(DraftFactory.makeDraft(from: message, extraction: extraction, household: household))
            } catch {
                drafts.append(fallbackDraft(from: message, error: error))
            }
        }

        return drafts
    }

    private func fallbackDraft(from email: SourceEmail, error: Error) -> InboxDraft {
        var draft = InboxDraft.pending(
            source: email,
            title: email.subject,
            dueDate: nil,
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0,
            evidence: email.bodyPreview.isEmpty ? [] : [email.bodyPreview]
        )
        draft.lastError = "Extraction failed: \(error.localizedDescription)"
        return draft
    }
}

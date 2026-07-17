import Foundation

public struct GmailReplyDraft: Equatable, Sendable {
    public var to: String
    public var subject: String
    public var body: String

    public init(to: String, subject: String, body: String) {
        self.to = to
        self.subject = subject
        self.body = body
    }
}

public struct GmailDraftReference: Equatable, Codable, Sendable {
    public var id: String
    public var messageID: String?

    public init(id: String, messageID: String? = nil) {
        self.id = id
        self.messageID = messageID
    }
}

public protocol GmailDraftClient: Sendable {
    func saveDraft(_ reply: GmailReplyDraft, existingDraftID: String?) async throws -> GmailDraftReference
}

public enum GmailReplyComposer {
    public static func replyDraft(for draft: InboxDraft, body: String) -> GmailReplyDraft {
        GmailReplyDraft(
            to: recipient(from: draft.source.from),
            subject: replySubject(for: draft.source.subject),
            body: body
        )
    }

    public static func composeURL(for reply: GmailReplyDraft) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "mail.google.com"
        components.path = "/mail/u/0/"
        components.queryItems = [
            URLQueryItem(name: "view", value: "cm"),
            URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "to", value: reply.to),
            URLQueryItem(name: "su", value: reply.subject),
            URLQueryItem(name: "body", value: reply.body)
        ]

        return components.url ?? URL(string: "https://mail.google.com/mail/u/0/")!
    }

    static func recipient(from sender: String) -> String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let openIndex = trimmed.lastIndex(of: "<"),
           let closeIndex = trimmed[openIndex...].firstIndex(of: ">") {
            let email = trimmed[trimmed.index(after: openIndex)..<closeIndex]
            return String(email).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func replySubject(for subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("re:") {
            return trimmed
        }
        return "Re: \(trimmed)"
    }
}

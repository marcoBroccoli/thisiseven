import Foundation

/// The draft passed to Gmail after a household member has reviewed the reply.
/// Even does not hold Gmail send permission and never sends on the user's behalf.
public struct GmailReplyDraft: Hashable, Sendable {
    public let recipient: String
    public let subject: String
    public let body: String
}

public enum GmailReplyComposer {
    public static func draft(sourceFrom: String, sourceSubject: String, body: String) -> GmailReplyDraft? {
        guard let recipient = recipient(from: sourceFrom) else { return nil }
        let source = sourceSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = source.lowercased().hasPrefix("re:") ? source : "Re: \(source)"
        return GmailReplyDraft(recipient: recipient, subject: subject, body: body)
    }

    public static func composeURL(for draft: GmailReplyDraft) -> URL {
        var components = URLComponents(string: "https://mail.google.com/mail/u/0/")!
        components.queryItems = [
            URLQueryItem(name: "view", value: "cm"),
            URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "to", value: draft.recipient),
            URLQueryItem(name: "su", value: draft.subject),
            URLQueryItem(name: "body", value: draft.body),
        ]
        return components.url!
    }

    private static func recipient(from sourceFrom: String) -> String? {
        let raw: String
        if let start = sourceFrom.firstIndex(of: "<"),
           let end = sourceFrom[start...].firstIndex(of: ">") {
            raw = String(sourceFrom[sourceFrom.index(after: start)..<end])
        } else {
            raw = sourceFrom
        }
        let recipient = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recipient.contains("@"), !recipient.contains(" ") else { return nil }
        return recipient
    }
}

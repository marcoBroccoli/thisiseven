import Foundation

public struct GmailAPIHeader: Equatable, Codable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct GmailAPIMessage: Equatable, Codable, Sendable {
    public var id: String
    public var snippet: String
    public var internalDateMilliseconds: String
    public var headers: [GmailAPIHeader]

    public init(id: String, snippet: String, internalDateMilliseconds: String, headers: [GmailAPIHeader]) {
        self.id = id
        self.snippet = snippet
        self.internalDateMilliseconds = internalDateMilliseconds
        self.headers = headers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""

        if let internalDate = try container.decodeIfPresent(String.self, forKey: .internalDate) {
            internalDateMilliseconds = internalDate
        } else {
            internalDateMilliseconds = try container.decode(String.self, forKey: .internalDateMilliseconds)
        }

        if let rootHeaders = try container.decodeIfPresent([GmailAPIHeader].self, forKey: .headers) {
            headers = rootHeaders
        } else {
            let payload = try container.decode(GmailAPIPayload.self, forKey: .payload)
            headers = payload.headers
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(snippet, forKey: .snippet)
        try container.encode(internalDateMilliseconds, forKey: .internalDate)
        try container.encode(GmailAPIPayload(headers: headers), forKey: .payload)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case snippet
        case internalDate
        case internalDateMilliseconds
        case headers
        case payload
    }
}

private struct GmailAPIPayload: Equatable, Codable, Sendable {
    var headers: [GmailAPIHeader]
}

public enum GmailMessageMapperError: Error, Equatable {
    case missingHeader(String)
    case invalidInternalDate(String)
}

public enum GmailMessageMapper {
    public static func sourceEmail(from message: GmailAPIMessage, label: String) throws -> SourceEmail {
        let headers = Dictionary(uniqueKeysWithValues: message.headers.map { ($0.name.lowercased(), $0.value) })

        guard let subject = headers["subject"] else {
            throw GmailMessageMapperError.missingHeader("Subject")
        }

        guard let from = headers["from"] else {
            throw GmailMessageMapperError.missingHeader("From")
        }

        guard let milliseconds = TimeInterval(message.internalDateMilliseconds) else {
            throw GmailMessageMapperError.invalidInternalDate(message.internalDateMilliseconds)
        }

        return SourceEmail(
            gmailMessageID: message.id,
            subject: subject,
            from: from,
            receivedAt: Date(timeIntervalSince1970: milliseconds / 1_000),
            label: label,
            bodyPreview: message.snippet
        )
    }
}

public struct GoogleCalendarPayload: Equatable, Codable, Sendable {
    public var summary: String
    public var description: String
    public var start: GoogleCalendarDateTime
    public var end: GoogleCalendarDateTime
    public var attendees: [GoogleCalendarAttendee]
    public var reminders: GoogleCalendarReminders
    public var recurrence: [String]?
}

public struct GoogleCalendarDateTime: Equatable, Codable, Sendable {
    public var dateTime: String
    public var timeZone: String
}

public struct GoogleCalendarAttendee: Equatable, Codable, Sendable {
    public var email: String
}

public struct GoogleCalendarReminders: Equatable, Codable, Sendable {
    public var useDefault: Bool
    public var overrides: [GoogleCalendarReminder]
}

public struct GoogleCalendarReminder: Equatable, Codable, Sendable {
    public var method: String
    public var minutes: Int
}

public enum GoogleCalendarPayloadFactory {
    public static func payload(from event: CalendarEventDraft) -> GoogleCalendarPayload {
        GoogleCalendarPayload(
            summary: event.title,
            description: "\(event.notes)\n\nOpen in Household Command Center: \(event.appURL.absoluteString)",
            start: GoogleCalendarDateTime(dateTime: iso8601String(from: event.dueDate), timeZone: "UTC"),
            end: GoogleCalendarDateTime(dateTime: iso8601String(from: event.dueDate.addingTimeInterval(30 * 60)), timeZone: "UTC"),
            attendees: event.attendeeEmails.map { GoogleCalendarAttendee(email: $0) },
            reminders: GoogleCalendarReminders(
                useDefault: false,
                overrides: event.reminderMinutesBefore.map { GoogleCalendarReminder(method: "popup", minutes: $0) }
            ),
            recurrence: event.recurrenceRule.map { [$0] }
        )
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

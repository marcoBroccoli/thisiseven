import Foundation

public protocol CalendarClient: Sendable {
    func createEvent(_ event: CalendarEventDraft) async throws -> CalendarEventReference
    func updateEvent(id eventID: String, with event: CalendarEventDraft) async throws -> CalendarEventReference
    func eventStatus(for eventID: String) async throws -> CalendarEventSyncState
    func eventSnapshot(for eventID: String) async throws -> CalendarEventSnapshot?
}

public extension CalendarClient {
    func updateEvent(id eventID: String, with event: CalendarEventDraft) async throws -> CalendarEventReference {
        throw CalendarClientError.creationFailed("Calendar update is not supported by this client.")
    }

    func eventSnapshot(for eventID: String) async throws -> CalendarEventSnapshot? {
        nil
    }
}

public struct CalendarEventDraft: Equatable, Codable, Sendable {
    public var calendarID: String
    public var title: String
    public var dueDate: Date
    public var notes: String
    public var attendeeEmails: [String]
    public var reminderMinutesBefore: [Int]
    public var appURL: URL

    public init(
        calendarID: String,
        title: String,
        dueDate: Date,
        notes: String,
        attendeeEmails: [String],
        reminderMinutesBefore: [Int],
        appURL: URL
    ) {
        self.calendarID = calendarID
        self.title = title
        self.dueDate = dueDate
        self.notes = notes
        self.attendeeEmails = attendeeEmails
        self.reminderMinutesBefore = reminderMinutesBefore
        self.appURL = appURL
    }
}

public struct CalendarEventReference: Equatable, Codable, Sendable {
    public var id: String
    public var url: URL?

    public init(id: String, url: URL?) {
        self.id = id
        self.url = url
    }
}

public struct CalendarEventSnapshot: Equatable, Codable, Sendable {
    public var title: String
    public var dueDate: Date
    public var notes: String?
    public var url: URL?
    public var capturedAt: Date

    public init(title: String, dueDate: Date, notes: String?, url: URL?, capturedAt: Date) {
        self.title = title
        self.dueDate = dueDate
        self.notes = notes
        self.url = url
        self.capturedAt = capturedAt
    }
}

public enum CalendarEventSyncState: Equatable, Codable, Sendable {
    case present
    case deleted
    case modifiedExternally
}

public enum CalendarClientError: Error, Equatable, LocalizedError, Sendable {
    case creationFailed(String)
    case missingDueDate
    case missingCalendarConnection

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let message):
            message
        case .missingDueDate:
            "A due date is required before creating a Google Calendar event."
        case .missingCalendarConnection:
            "Google Calendar is not connected for this household."
        }
    }
}

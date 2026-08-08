import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct GoogleClient: Sendable {
    public var status: @Sendable () async throws -> GoogleStatus = {
        throw GoogleClientError.unimplemented
    }

    public var startSync: @Sendable () async throws -> GoogleSyncStart = {
        throw GoogleClientError.unimplemented
    }

    /// OAuth presentation — Live will bridge ASWebAuthenticationSession later.
    public var connect: @Sendable () async throws -> Void = {
        throw GoogleClientError.unimplemented
    }

    public var disconnect: @Sendable () async throws -> Void = {
        throw GoogleClientError.unimplemented
    }

    /// The household's shared calendar plus the caller's standing on it
    /// (owner / listed / can add).
    public var calendarInfo: @Sendable () async throws -> GoogleCalendarInfo = {
        throw GoogleClientError.unimplemented
    }

    /// One-tap confirm: put the shared calendar on the caller's Google.
    public var addSharedCalendar: @Sendable () async throws -> GoogleCalendarAddResult = {
        throw GoogleClientError.unimplemented
    }
}

public enum GoogleClientError: Error, Sendable {
    case unimplemented
}

extension GoogleClient: TestDependencyKey {
    public static let testValue = GoogleClient()

    /// Safe canvas default — no Live / network. Features still override per preview.
    public static let previewValue = GoogleClient(
        status: { PreviewData.googleDisconnected },
        startSync: { GoogleSyncStart(started: false) },
        connect: {},
        disconnect: {},
        calendarInfo: { PreviewData.calendarInfoCanAdd },
        addSharedCalendar: { PreviewData.calendarAdded }
    )
}

public extension DependencyValues {
    var googleClient: GoogleClient {
        get { self[GoogleClient.self] }
        set { self[GoogleClient.self] = newValue }
    }
}

import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct CalendarClient: Sendable {
    public var window: @Sendable (_ from: String, _ to: String) async throws -> CalendarResponse = { _, _ in
        throw CalendarClientError.unimplemented
    }

    public var sync: @Sendable () async throws -> CalendarSyncResult = {
        throw CalendarClientError.unimplemented
    }
}

public enum CalendarClientError: Error, Sendable {
    case unimplemented
}

extension CalendarClient: TestDependencyKey {
    public static let testValue = CalendarClient()

    /// Canvas default — August fixture window; sync is a no-op success.
    public static let previewValue = CalendarClient(
        window: { _, _ in PreviewData.calendarMonth },
        sync: { PreviewData.calendarSync }
    )
}

public extension DependencyValues {
    var calendarClient: CalendarClient {
        get { self[CalendarClient.self] }
        set { self[CalendarClient.self] = newValue }
    }
}

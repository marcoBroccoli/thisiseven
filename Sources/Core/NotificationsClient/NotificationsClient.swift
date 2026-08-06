import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct NotificationsClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Bool = { false }
    public var scheduleReminders: @Sendable () async -> Void = {}
}

extension NotificationsClient: TestDependencyKey {
    public static let testValue = NotificationsClient()

    /// Canvas default — permission granted; schedule is a no-op.
    public static let previewValue = NotificationsClient(
        requestAuthorization: { true },
        scheduleReminders: {}
    )
}

public extension DependencyValues {
    var notificationsClient: NotificationsClient {
        get { self[NotificationsClient.self] }
        set { self[NotificationsClient.self] = newValue }
    }
}

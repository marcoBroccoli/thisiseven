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
}

public extension DependencyValues {
    var notificationsClient: NotificationsClient {
        get { self[NotificationsClient.self] }
        set { self[NotificationsClient.self] = newValue }
    }
}

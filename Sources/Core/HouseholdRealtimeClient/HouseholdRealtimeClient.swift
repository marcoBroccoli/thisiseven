import Dependencies
import DependenciesMacros
import Foundation

/// Server → client household bus event (`GET /v1/ws/household`).
public struct HouseholdRealtimeEvent: Equatable, Sendable {
    public var type: String
    public var scopes: [String]
    public var reason: String
    public var actorMemberId: UUID?

    public init(
        type: String = "household.invalidate",
        scopes: [String],
        reason: String,
        actorMemberId: UUID? = nil
    ) {
        self.type = type
        self.scopes = scopes
        self.reason = reason
        self.actorMemberId = actorMemberId
    }

    public var invalidatesSummary: Bool {
        type == "household.invalidate" && scopes.contains("summary")
    }
}

@DependencyClient
public struct HouseholdRealtimeClient: Sendable {
    /// Long-lived stream of household invalidate (and future) events while the
    /// consumer iterates. Cancelling the stream disconnects.
    public var events: @Sendable () -> AsyncStream<HouseholdRealtimeEvent> = {
        AsyncStream { $0.finish() }
    }
}

extension HouseholdRealtimeClient: TestDependencyKey {
    public static let testValue = HouseholdRealtimeClient()

    /// Canvas / preview — idle empty stream (no socket).
    public static let previewValue = HouseholdRealtimeClient(
        events: { AsyncStream { $0.finish() } }
    )
}

public extension DependencyValues {
    var householdRealtimeClient: HouseholdRealtimeClient {
        get { self[HouseholdRealtimeClient.self] }
        set { self[HouseholdRealtimeClient.self] = newValue }
    }
}

import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct HouseholdClient: Sendable {
    public var create: @Sendable (_ name: String, _ displayName: String) async throws -> Household = { _, _ in
        throw HouseholdClientError.unimplemented
    }

    public var join: @Sendable (_ inviteCode: String, _ displayName: String) async throws -> Household = { _, _ in
        throw HouseholdClientError.unimplemented
    }
}

public enum HouseholdClientError: Error, Sendable {
    case unimplemented
}

extension HouseholdClient: TestDependencyKey {
    public static let testValue = HouseholdClient()

    /// Canvas default — create/join return The Attic.
    public static let previewValue = HouseholdClient(
        create: { _, _ in PreviewData.household },
        join: { _, _ in PreviewData.household }
    )
}

public extension DependencyValues {
    var householdClient: HouseholdClient {
        get { self[HouseholdClient.self] }
        set { self[HouseholdClient.self] = newValue }
    }
}

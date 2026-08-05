import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct DraftsClient: Sendable {
    public var pending: @Sendable () async throws -> [Draft] = { [] }
    public var update: @Sendable (_ id: UUID, _ body: EvenAPIClient.DraftPatchBody) async throws -> Draft = { _, _ in
        throw DraftsClientError.unimplemented
    }

    public var approve: @Sendable (_ id: UUID) async throws -> EvenAPIClient.ApproveResponse = { _ in
        throw DraftsClientError.unimplemented
    }

    public var dismiss: @Sendable (_ id: UUID) async throws -> Draft = { _ in
        throw DraftsClientError.unimplemented
    }
}

public enum DraftsClientError: Error, Sendable {
    case unimplemented
}

extension DraftsClient: TestDependencyKey {
    public static let testValue = DraftsClient()
}

public extension DependencyValues {
    var draftsClient: DraftsClient {
        get { self[DraftsClient.self] }
        set { self[DraftsClient.self] = newValue }
    }
}

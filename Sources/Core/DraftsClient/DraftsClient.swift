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

    /// Canvas default — pending fixtures; approve/dismiss resolve against PreviewData.
    public static let previewValue = DraftsClient(
        pending: { PreviewData.pendingDrafts },
        update: { id, _ in
            PreviewData.pendingDrafts.first { $0.id == id } ?? PreviewData.pendingDrafts[0]
        },
        approve: { _ in
            EvenAPIClient.ApproveResponse(
                draft: PreviewData.pendingDrafts[0],
                task: PreviewData.waterBill
            )
        },
        dismiss: { id in
            PreviewData.pendingDrafts.first { $0.id == id } ?? PreviewData.pendingDrafts[0]
        }
    )
}

public extension DependencyValues {
    var draftsClient: DraftsClient {
        get { self[DraftsClient.self] }
        set { self[DraftsClient.self] = newValue }
    }
}

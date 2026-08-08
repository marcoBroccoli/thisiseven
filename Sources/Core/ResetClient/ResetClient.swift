import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

/// The Sunday ritual's data seam: what the week weighed, the kind thing each
/// side wrote, and the pour that closes it.
@DependencyClient
public struct ResetClient: Sendable {
    public var fetch: @Sendable () async throws -> ResetSummary = {
        throw ResetClientError.unimplemented
    }

    /// Upsert *my* appreciation for the open week. The API rejects this for a
    /// solo household — the ritual skips the beat entirely there.
    public var setMyAppreciation: @Sendable (_ body: String?, _ said: Bool) async throws
        -> Appreciation = { _, _ in
            throw ResetClientError.unimplemented
        }

    /// Only the side that did *not* propose the trade can accept it.
    public var acceptTrade: @Sendable (_ id: UUID, _ accepted: Bool) async throws -> Trade = { _, _ in
        throw ResetClientError.unimplemented
    }

    /// Pour the week out. `weekId` guards a double-tap; the server answers 409
    /// `week_already_closed` when the open week has already moved on.
    public var closeWeek: @Sendable (_ weekId: UUID?) async throws -> WeekCloseResponse = { _ in
        throw ResetClientError.unimplemented
    }
}

public enum ResetClientError: Error, Sendable {
    case unimplemented
}

extension ResetClient: TestDependencyKey {
    public static let testValue = ResetClient()

    /// Canvas default — a partnered week leaning Ada, partner's kind thing waiting.
    public static let previewValue = ResetClient(
        fetch: { PreviewData.resetSummary },
        setMyAppreciation: { body, said in
            Appreciation(
                id: PreviewData.appreciationFromMe.id,
                fromMemberId: PreviewData.adaId,
                toMemberId: PreviewData.umutId,
                body: body,
                said: said
            )
        },
        acceptTrade: { id, accepted in
            Trade(
                id: id,
                taskId: PreviewData.pendingTrade.taskId,
                taskTitle: PreviewData.pendingTrade.taskTitle,
                fromMemberId: PreviewData.pendingTrade.fromMemberId,
                toMemberId: PreviewData.pendingTrade.toMemberId,
                accepted: accepted
            )
        },
        closeWeek: { _ in PreviewData.weekClose }
    )
}

public extension DependencyValues {
    var resetClient: ResetClient {
        get { self[ResetClient.self] }
        set { self[ResetClient.self] = newValue }
    }
}

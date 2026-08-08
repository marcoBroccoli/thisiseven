import Dependencies
import EvenCore
import Foundation
import ResetClient

extension ResetClient: DependencyKey {
    public static let liveValue = ResetClient(
        fetch: {
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.resetSummary()
        },
        setMyAppreciation: { body, said in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.setMyAppreciation(body: body, said: said)
        },
        acceptTrade: { id, accepted in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.acceptTrade(id: id, accepted: accepted)
        },
        closeWeek: { weekId in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.closeWeek(weekId: weekId)
        }
    )
}

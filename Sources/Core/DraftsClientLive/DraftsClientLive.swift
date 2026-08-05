import Dependencies
import DraftsClient
import EvenCore
import Foundation

extension DraftsClient: DependencyKey {
    public static let liveValue = DraftsClient(
        pending: {
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.pendingDrafts()
        },
        update: { id, body in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.updateDraft(id: id, body)
        },
        approve: { id in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.approveDraft(id: id)
        },
        dismiss: { id in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.dismissDraft(id: id)
        }
    )
}

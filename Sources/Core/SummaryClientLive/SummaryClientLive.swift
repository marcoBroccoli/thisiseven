import Dependencies
import EvenCore
import Foundation
import SummaryClient

extension SummaryClient: DependencyKey {
    public static let liveValue = SummaryClient(
        fetch: {
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.summary()
        }
    )
}

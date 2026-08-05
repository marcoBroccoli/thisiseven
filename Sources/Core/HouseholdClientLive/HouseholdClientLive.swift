import Dependencies
import EvenCore
import Foundation
import HouseholdClient

extension HouseholdClient: DependencyKey {
    public static let liveValue = HouseholdClient(
        create: { name, displayName in
            let store = await MainActor.run { SharedSession.store }
            try await store.createHousehold(name: name, displayName: displayName)
            guard let household = await MainActor.run(body: { SharedSession.store.me?.household }) else {
                throw HouseholdClientError.unimplemented
            }
            return household
        },
        join: { code, displayName in
            let store = await MainActor.run { SharedSession.store }
            try await store.joinHousehold(inviteCode: code, displayName: displayName)
            guard let household = await MainActor.run(body: { SharedSession.store.me?.household }) else {
                throw HouseholdClientError.unimplemented
            }
            return household
        }
    )
}

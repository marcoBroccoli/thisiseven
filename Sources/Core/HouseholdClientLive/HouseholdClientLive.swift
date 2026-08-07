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
        },
        loadProfile: {
            let store = await MainActor.run { SharedSession.store }
            return try await store.loadProfile()
        },
        updateMe: { displayName, color in
            let store = await MainActor.run { SharedSession.store }
            return try await store.updateMe(displayName: displayName, color: color)
        },
        uploadAvatar: { jpeg in
            let store = await MainActor.run { SharedSession.store }
            return try await store.uploadAvatar(jpeg: jpeg)
        },
        deleteAvatar: {
            let store = await MainActor.run { SharedSession.store }
            return try await store.deleteAvatar()
        },
        fetchAvatar: { memberId in
            let store = await MainActor.run { SharedSession.store }
            return try await store.fetchAvatar(memberId: memberId)
        }
    )
}

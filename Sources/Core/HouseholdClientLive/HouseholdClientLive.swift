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
        list: {
            let store = await MainActor.run { SharedSession.store }
            return try await store.households()
        },
        invite: { householdId, email in
            let store = await MainActor.run { SharedSession.store }
            return try await store.invite(householdId: householdId, email: email)
        },
        revokeInvite: { householdId in
            let store = await MainActor.run { SharedSession.store }
            try await store.revokeInvite(householdId: householdId)
        },
        acceptInvite: { inviteId, displayName in
            let store = await MainActor.run { SharedSession.store }
            return try await store.acceptInvite(id: inviteId, displayName: displayName)
        },
        declineInvite: { inviteId in
            let store = await MainActor.run { SharedSession.store }
            try await store.declineInvite(id: inviteId)
        },
        leave: { householdId in
            let store = await MainActor.run { SharedSession.store }
            return try await store.leaveHousehold(id: householdId)
        },
        setActive: { householdId in
            let store = await MainActor.run { SharedSession.store }
            return try await store.setActiveHousehold(householdId)
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

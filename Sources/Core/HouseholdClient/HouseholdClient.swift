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

    /// Every household the caller sits in + invites waiting on their email.
    /// Answers before any membership exists — onboarding leans on that.
    public var list: @Sendable () async throws -> HouseholdsResponse = {
        throw HouseholdClientError.unimplemented
    }

    /// Record the free seat's address. No mail is sent — the invitee finds it
    /// on their own `list()`.
    public var invite: @Sendable (_ householdId: UUID, _ email: String) async throws -> HouseholdInvite = { _, _ in
        throw HouseholdClientError.unimplemented
    }

    public var revokeInvite: @Sendable (_ householdId: UUID) async throws -> Void = { _ in
        throw HouseholdClientError.unimplemented
    }

    public var acceptInvite: @Sendable (_ inviteId: UUID, _ displayName: String) async throws -> Household = { _, _ in
        throw HouseholdClientError.unimplemented
    }

    public var declineInvite: @Sendable (_ inviteId: UUID) async throws -> Void = { _ in
        throw HouseholdClientError.unimplemented
    }

    /// Give up your seat. Archives your open todos there, disconnects your
    /// Gmail for that household, keeps the shared history — and deletes the
    /// household when you were the last one in it.
    public var leave: @Sendable (_ householdId: UUID) async throws -> LeaveHouseholdResult = { _ in
        throw HouseholdClientError.unimplemented
    }

    /// Point every later request at this household and re-read `/v1/me` through
    /// it. The id is persisted, so the socket and the widgets follow too.
    public var setActive: @Sendable (_ householdId: UUID) async throws -> MeResponse = { _ in
        throw HouseholdClientError.unimplemented
    }

    public var loadProfile: @Sendable () async throws -> MeResponse = {
        throw HouseholdClientError.unimplemented
    }

    public var updateMe: @Sendable (_ displayName: String?, _ color: MemberColor?) async throws -> Member = { _, _ in
        throw HouseholdClientError.unimplemented
    }

    public var uploadAvatar: @Sendable (_ jpeg: Data) async throws -> Member = { _ in
        throw HouseholdClientError.unimplemented
    }

    public var deleteAvatar: @Sendable () async throws -> Member = {
        throw HouseholdClientError.unimplemented
    }

    public var fetchAvatar: @Sendable (_ memberId: UUID) async throws -> Data = { _ in
        throw HouseholdClientError.unimplemented
    }
}

public enum HouseholdClientError: Error, Sendable {
    case unimplemented
}

extension HouseholdClient: TestDependencyKey {
    public static let testValue = HouseholdClient()

    /// Canvas default — create/join return The Attic; profile is Ada/Umut.
    public static let previewValue = HouseholdClient(
        create: { _, _ in PreviewData.household },
        join: { _, _ in PreviewData.household },
        list: { PreviewData.households },
        invite: { householdId, email in
            HouseholdInvite(
                id: UUID(),
                householdId: householdId,
                householdName: PreviewData.household.name,
                invitedByName: PreviewData.ada.displayName,
                email: email
            )
        },
        revokeInvite: { _ in },
        acceptInvite: { _, _ in PreviewData.household },
        declineInvite: { _ in },
        leave: { _ in LeaveHouseholdResult(ok: true, householdDeleted: false) },
        setActive: { _ in PreviewData.me },
        loadProfile: { PreviewData.me },
        updateMe: { displayName, color in
            var member = PreviewData.ada
            if let displayName { member.displayName = displayName }
            if let color { member.color = color }
            return member
        },
        uploadAvatar: { jpeg in
            await MemberAvatarCache.shared.store(PreviewData.ada.id, data: jpeg)
            var member = PreviewData.ada
            member.hasAvatar = true
            return member
        },
        deleteAvatar: {
            await MemberAvatarCache.shared.remove(PreviewData.ada.id)
            var member = PreviewData.ada
            member.hasAvatar = false
            return member
        },
        fetchAvatar: { memberId in
            if let cached = await MemberAvatarCache.shared.data(for: memberId) {
                return cached
            }
            throw HouseholdClientError.unimplemented
        }
    )
}

public extension DependencyValues {
    var householdClient: HouseholdClient {
        get { self[HouseholdClient.self] }
        set { self[HouseholdClient.self] = newValue }
    }
}

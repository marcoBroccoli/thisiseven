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

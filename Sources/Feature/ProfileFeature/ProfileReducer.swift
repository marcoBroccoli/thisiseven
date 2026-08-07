import AuthClient
import ComposableArchitecture
import ConnectionsFeature
import EvenCore
import Foundation
import HouseholdClient
import ToastClient
import ToastUI

@Reducer
public struct ProfileReducer {
    @ObservableState
    public struct State: Equatable {
        public var me: Member?
        public var partner: Member?
        public var householdName = ""
        public var inviteCode = ""
        public var draftDisplayName = ""
        public var isLoading = true
        public var isSaving = false
        public var nameError: String?
        public var confirmSignOut = false
        public var connections = ConnectionsReducer.State()
        /// Local JPEG preview while upload is in flight / just picked.
        public var localAvatarJPEG: Data?

        public init() {}

        public var googleConnected: Bool {
            connections.email != nil || connections.path == .connected
        }
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)
        case connections(ConnectionsReducer.Action)
        case profileLoaded(MeResponse)
        case profileLoadFailed
        case saveSucceeded(Member)
        case saveFailed(previousName: String, previousColor: MemberColor)
        case avatarUploadSucceeded(Member)
        case avatarUploadFailed
        case avatarDeleteSucceeded(Member)
        case avatarDeleteFailed
        case presentToast(Toast)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case refresh
            case commitDisplayName
            case selectColor(MemberColor)
            case pickAvatarJPEG(Data)
            case removeAvatar
            case inviteCopied
            case signOutTapped
            case confirmSignOut
            case cancelSignOut
            case connectGoogleTapped
        }

        @CasePathable
        public enum Delegate: Equatable {
            /// Session cleared — App should return to Login.
            case signedOut
        }
    }

    @Dependency(\.householdClient) var householdClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.toastClient) var toastClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Scope(state: \.connections, action: \.connections) { ConnectionsReducer() }
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .view(.appear), .view(.refresh):
                if state.me == nil {
                    state.isLoading = true
                }
                return .merge(
                    .send(.connections(.view(.appear))),
                    loadProfile()
                )

            case let .profileLoaded(me):
                state.isLoading = false
                apply(me, to: &state)
                return .none

            case .profileLoadFailed:
                state.isLoading = false
                return toastEffect(.init(message: "Couldn’t load profile", tone: .error))

            case .view(.commitDisplayName):
                let trimmed = state.draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    state.nameError = "Name can’t be empty"
                    return .none
                }
                guard trimmed.count <= 40 else {
                    state.nameError = "Name is too long"
                    return .none
                }
                state.nameError = nil
                guard trimmed != state.me?.displayName else { return .none }
                guard !state.isSaving else { return .none }
                let previousName = state.me?.displayName ?? trimmed
                let previousColor = state.me?.color ?? .clay
                state.me?.displayName = trimmed
                state.draftDisplayName = trimmed
                state.isSaving = true
                return save(displayName: trimmed, color: nil, previousName: previousName, previousColor: previousColor)

            case let .view(.selectColor(color)):
                guard state.me?.color != color else { return .none }
                guard !state.isSaving else { return .none }
                let previousName = state.me?.displayName ?? state.draftDisplayName
                let previousColor = state.me?.color ?? .clay
                state.me?.color = color
                state.isSaving = true
                return save(displayName: nil, color: color, previousName: previousName, previousColor: previousColor)

            case let .view(.pickAvatarJPEG(jpeg)):
                guard !state.isSaving else { return .none }
                state.localAvatarJPEG = jpeg
                state.me?.hasAvatar = true
                state.isSaving = true
                return .run { [householdClient] send in
                    do {
                        let member = try await householdClient.uploadAvatar(jpeg)
                        await send(.avatarUploadSucceeded(member))
                    } catch {
                        await send(.avatarUploadFailed)
                    }
                }

            case .view(.removeAvatar):
                guard state.me?.hasAvatar == true || state.localAvatarJPEG != nil else { return .none }
                guard !state.isSaving else { return .none }
                state.localAvatarJPEG = nil
                state.me?.hasAvatar = false
                state.isSaving = true
                return .run { [householdClient] send in
                    do {
                        let member = try await householdClient.deleteAvatar()
                        await send(.avatarDeleteSucceeded(member))
                    } catch {
                        await send(.avatarDeleteFailed)
                    }
                }

            case let .saveSucceeded(member):
                state.isSaving = false
                state.me = member
                state.draftDisplayName = member.displayName
                return .none

            case let .saveFailed(previousName, previousColor):
                state.isSaving = false
                state.me?.displayName = previousName
                state.me?.color = previousColor
                state.draftDisplayName = previousName
                return toastEffect(.init(message: "Couldn’t save profile", tone: .error))

            case let .avatarUploadSucceeded(member):
                state.isSaving = false
                state.me = member
                state.localAvatarJPEG = nil
                return .none

            case .avatarUploadFailed:
                state.isSaving = false
                state.localAvatarJPEG = nil
                state.me?.hasAvatar = false
                return toastEffect(.init(message: "Couldn’t upload photo", tone: .error))

            case let .avatarDeleteSucceeded(member):
                state.isSaving = false
                state.me = member
                state.localAvatarJPEG = nil
                return .none

            case .avatarDeleteFailed:
                state.isSaving = false
                state.me?.hasAvatar = true
                return toastEffect(.init(message: "Couldn’t remove photo", tone: .error))

            case .view(.inviteCopied):
                return toastEffect(.init(message: "Invite code copied"))

            case .view(.signOutTapped):
                state.confirmSignOut = true
                return .none

            case .view(.cancelSignOut):
                state.confirmSignOut = false
                return .none

            case .view(.confirmSignOut):
                state.confirmSignOut = false
                return .run { [authClient] send in
                    await authClient.signOut()
                    await send(.delegate(.signedOut))
                }

            case .delegate:
                return .none

            case .view(.connectGoogleTapped):
                return .send(.connections(.view(.primaryTapped)))

            case .connections, .presentToast:
                return .none
            }
        }
    }

    private func loadProfile() -> Effect<Action> {
        .run { [householdClient] send in
            do {
                try await send(.profileLoaded(await householdClient.loadProfile()))
            } catch {
                await send(.profileLoadFailed)
            }
        }
    }

    private func save(
        displayName: String?,
        color: MemberColor?,
        previousName: String,
        previousColor: MemberColor
    ) -> Effect<Action> {
        .run { [householdClient] send in
            do {
                let member = try await householdClient.updateMe(displayName, color)
                await send(.saveSucceeded(member))
            } catch {
                await send(.saveFailed(previousName: previousName, previousColor: previousColor))
            }
        }
    }

    private func toastEffect(_ toast: Toast) -> Effect<Action> {
        .run { [toastClient] _ in
            await toastClient.show(toast)
        }
    }

    private func apply(_ me: MeResponse, to state: inout State) {
        state.me = me.member ?? me.household?.me
        state.partner = me.household?.partner
        state.householdName = me.household?.name ?? ""
        state.inviteCode = me.household?.inviteCode ?? ""
        state.draftDisplayName = state.me?.displayName ?? ""
        state.nameError = nil
        state.localAvatarJPEG = nil
    }
}

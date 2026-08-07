import ComposableArchitecture
import ConnectionsFeature
import EvenCore
import Foundation
import GoogleClient
import HouseholdClient
import ToastClient

public enum ProfilePreviewSupport {
    @MainActor
    public static func populated() -> StoreOf<ProfileReducer> {
        var state = ProfileReducer.State()
        state.isLoading = false
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.householdName = PreviewData.household.name
        state.inviteCode = PreviewData.household.inviteCode
        state.draftDisplayName = PreviewData.ada.displayName
        state.connections.email = PreviewData.googleConnected.email
        state.connections.path = .connected
        return Store(initialState: state) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient = .previewValue
            $0.toastClient = .silent()
            $0.googleClient.status = { PreviewData.googleConnected }
        }
    }

    @MainActor
    public static func loading() -> StoreOf<ProfileReducer> {
        Store(initialState: ProfileReducer.State()) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient.loadProfile = {
                try await Task.sleep(for: .seconds(60))
                return PreviewData.me
            }
            $0.toastClient = .silent()
            $0.googleClient.status = {
                try await Task.sleep(for: .seconds(60))
                return PreviewData.googleDisconnected
            }
        }
    }
}

import ComposableArchitecture
import EvenCore
import GoogleClient
import NotificationsClient

public enum ConnectionsPreviewSupport {
    public static func disconnected() -> StoreOf<ConnectionsFeature> {
        var state = ConnectionsFeature.State()
        state.statusLine = "Not connected"
        return Store(initialState: state) {
            ConnectionsFeature()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googleDisconnected }
            $0.googleClient.connect = {}
            $0.notificationsClient.requestAuthorization = { true }
        }
    }

    public static func connected() -> StoreOf<ConnectionsFeature> {
        var state = ConnectionsFeature.State()
        state.statusLine = "Connected"
        state.email = PreviewData.googleConnected.email
        return Store(initialState: state) {
            ConnectionsFeature()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googleConnected }
            $0.notificationsClient.requestAuthorization = { true }
        }
    }
}

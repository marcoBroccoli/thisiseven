import ComposableArchitecture
import EvenCore
import GoogleClient
import NotificationsClient

public enum ConnectionsPreviewSupport {
    /// Interactive whole-flow store: status → connect / skip (mocked Google + notifications).
    public static func flow() -> StoreOf<ConnectionsReducer> {
        Store(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(&deps, connected: false)
        }
    }

    public static func disconnected() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.statusLine = "Not connected"
        return Store(initialState: state) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(&deps, connected: false)
        }
    }

    public static func connected() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.statusLine = "Connected"
        state.email = PreviewData.googleConnected.email
        return Store(initialState: state) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(&deps, connected: true)
        }
    }

    private static func mockConnections(_ deps: inout DependencyValues, connected: Bool) {
        deps.googleClient.status = {
            connected ? PreviewData.googleConnected : PreviewData.googleDisconnected
        }
        deps.googleClient.connect = {}
        deps.notificationsClient.requestAuthorization = { true }
    }
}

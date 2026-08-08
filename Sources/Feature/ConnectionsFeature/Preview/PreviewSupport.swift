import ComposableArchitecture
import Design
import EvenCore
import Foundation
import GoogleClient
import ToastClient

/// Preview / canvas factories. Client closures are the FreeFlex-style “use cases”:
/// override + `PreviewDelay` to exercise real loading / error paths in the reducer.
public enum ConnectionsPreviewSupport {
    public static let defaultStatusLag: Duration = .milliseconds(800)
    public static let defaultConnectLag: Duration = .seconds(2)

    // MARK: - Interactive (effect-driven)

    /// Whole flow: status lag → Why; Connect lags then advances to scopes.
    public static func flow(
        statusLag: Duration = defaultStatusLag,
        connectLag: Duration = defaultConnectLag
    ) -> StoreOf<ConnectionsReducer> {
        Store(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(statusLag) { PreviewData.googleDisconnected },
                connect: PreviewDelay.delayed(connectLag),
                disconnect: PreviewDelay.delayed(.milliseconds(400)),
                presentToasts: true
            )
        }
    }

    /// Appear shows checking, then lands on Connected (already linked).
    public static func flowAlreadyConnected(
        statusLag: Duration = defaultStatusLag
    ) -> StoreOf<ConnectionsReducer> {
        Store(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(statusLag) { PreviewData.googleConnected },
                connect: PreviewDelay.delayed(defaultConnectLag),
                disconnect: PreviewDelay.delayed(.milliseconds(400)),
                presentToasts: true
            )
        }
    }

    /// Tap Connect → spinner → error toast (reducer path).
    public static func flowConnectFails(
        after connectLag: Duration = defaultConnectLag
    ) -> StoreOf<ConnectionsReducer> {
        Store(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(.milliseconds(200)) { PreviewData.googleDisconnected },
                connect: PreviewDelay.delayedThrow(connectLag, URLError(.notConnectedToInternet)),
                disconnect: PreviewDelay.delayed(.milliseconds(400)),
                presentToasts: true
            )
        }
    }

    /// Appear → error toast (via `toastClient` → `.evenToastHost()`).
    /// Throws immediately — `Task.sleep` lags often never advance under RenderPreview.
    public static func flowStatusFails(
        after statusLag: Duration = .zero
    ) -> StoreOf<ConnectionsReducer> {
        Store(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: statusLag == .zero
                    ? { throw URLError(.timedOut) }
                    : PreviewDelay.delayedThrow(statusLag, URLError(.timedOut)),
                connect: PreviewDelay.delayed(defaultConnectLag),
                disconnect: PreviewDelay.delayed(.milliseconds(400)),
                presentToasts: true
            )
        }
    }

    /// Settings: Disconnect lags then returns to Why when exercised.
    public static func flowDisconnectSlow(
        after disconnectLag: Duration = .seconds(2)
    ) -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email
        return Store(initialState: state) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(.milliseconds(100)) { PreviewData.googleConnected },
                connect: PreviewDelay.delayed(defaultConnectLag),
                disconnect: PreviewDelay.delayed(disconnectLag),
                presentToasts: true
            )
        }
    }

    // MARK: - Snapshots (seeded state — instant canvas)

    public static func why() -> StoreOf<ConnectionsReducer> {
        snapshot(.why, connected: false)
    }

    /// Static “Connecting…” without waiting on effects.
    public static func whyWorking() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .why
        state.working = true
        return hungStore(state)
    }

    public static func whyCheckingStatus() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .why
        state.isCheckingStatus = true
        return hungStore(state)
    }

    public static func scopes() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .scopes
        state.email = PreviewData.googleConnected.email
        return snapshotStore(state, connected: true)
    }

    public static func connected() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email
        state.partnerConnected = true
        return snapshotStore(state, connected: true)
    }

    /// Connected, but the partner has not linked a mailbox of their own — the
    /// copy has to say so without implying their inbox is visible.
    public static func connectedPartnerMissing() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email
        return snapshotStore(state, connected: true)
    }

    /// The bug this screen exists to prevent: a partner who joined by invite
    /// code sees their OWN not-connected state, not the other member's success.
    public static func whyPartnerConnected() -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = .why
        state.partnerConnected = true
        return Store(initialState: state) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(.milliseconds(50)) { PreviewData.googlePartnerConnectedOnly },
                connect: PreviewDelay.delayed(.milliseconds(50)),
                disconnect: PreviewDelay.delayed(.milliseconds(50))
            )
        }
    }

    /// Design 04 — Settings manage surface (not on the setup path).
    public static func settings() -> StoreOf<ConnectionsReducer> {
        connected()
    }

    // MARK: - Internals

    private static func snapshot(
        _ path: ConnectionsReducer.Path,
        connected: Bool
    ) -> StoreOf<ConnectionsReducer> {
        var state = ConnectionsReducer.State()
        state.path = path
        if connected {
            state.email = PreviewData.googleConnected.email
        }
        return snapshotStore(state, connected: connected)
    }

    private static func snapshotStore(
        _ state: ConnectionsReducer.State,
        connected: Bool
    ) -> StoreOf<ConnectionsReducer> {
        Store(initialState: state) {
            ConnectionsReducer()
        } withDependencies: { deps in
            let status = connected ? PreviewData.googleConnected : PreviewData.googleDisconnected
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(.milliseconds(50)) { status },
                connect: PreviewDelay.delayed(.milliseconds(50)),
                disconnect: PreviewDelay.delayed(.milliseconds(50))
            )
        }
    }

    /// Keeps effects from resolving so seeded busy flags stay visible in canvas.
    private static func hungStore(
        _ state: ConnectionsReducer.State
    ) -> StoreOf<ConnectionsReducer> {
        Store(initialState: state) {
            ConnectionsReducer()
        } withDependencies: { deps in
            mockConnections(
                &deps,
                status: PreviewDelay.delayed(.seconds(60)) { PreviewData.googleDisconnected },
                connect: PreviewDelay.delayed(.seconds(60)),
                disconnect: PreviewDelay.delayed(.seconds(60))
            )
        }
    }

    private static func mockConnections(
        _ deps: inout DependencyValues,
        status: @escaping @Sendable () async throws -> GoogleStatus,
        connect: @escaping @Sendable () async throws -> Void,
        disconnect: @escaping @Sendable () async throws -> Void,
        presentToasts: Bool = false
    ) {
        deps.googleClient.status = status
        deps.googleClient.connect = connect
        deps.googleClient.disconnect = disconnect
        deps.toastClient = presentToasts ? .hosted() : .silent()
    }
}

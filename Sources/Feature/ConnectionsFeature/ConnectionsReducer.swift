import ComposableArchitecture
import Design
import EvenCore
import Foundation
import GoogleClient
import NotificationsClient
import ToastClient
import ToastUI

@Reducer
public struct ConnectionsReducer {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var path: Path = .why
        public var email: String?
        public var working = false
        public var isCheckingStatus = false
        public var gmailEnabled = true
        public var calendarEnabled = true
        public init() {}

        public var showsBack: Bool {
            path == .scopes
        }

        public var canAllowScopes: Bool {
            gmailEnabled || calendarEnabled
        }

        public var isBusy: Bool {
            working || isCheckingStatus
        }

        /// Shell footer chrome — one primary + optional secondary; path only
        /// remaps titles, style, and availability.
        public var footer: Footer {
            switch path {
            case .why:
                Footer(
                    primary: .init(
                        style: .google,
                        title: working ? "Connecting…" : "Connect Google",
                        enabled: !isBusy,
                        working: working,
                        checkingStatus: isCheckingStatus,
                        accessibilityId: "Connect Google"
                    ),
                    secondary: .init(
                        style: .textLink,
                        title: "SKIP FOR NOW",
                        enabled: !isBusy,
                        accessibilityId: "Skip for now"
                    )
                )
            case .scopes:
                Footer(
                    primary: .init(
                        style: .filled,
                        title: "Allow & continue",
                        enabled: canAllowScopes,
                        accessibilityId: "Allow & continue"
                    ),
                    secondary: nil
                )
            case .connected:
                Footer(
                    primary: .init(
                        style: .filled,
                        title: "Go to Even",
                        enabled: true,
                        accessibilityId: "Go to Even"
                    ),
                    secondary: nil
                )
            }
        }
    }

    /// Fixed CTA slots the shell always renders; nil secondary collapses it.
    public struct Footer: Equatable, Sendable {
        public var primary: Button
        public var secondary: Button?

        public struct Button: Equatable, Sendable {
            public enum Style: Equatable, Sendable {
                case filled
                case google
                case textLink
            }

            public var style: Style
            public var title: String
            public var enabled: Bool
            public var working: Bool
            public var checkingStatus: Bool
            public var accessibilityId: String

            public init(
                style: Style,
                title: String,
                enabled: Bool,
                working: Bool = false,
                checkingStatus: Bool = false,
                accessibilityId: String
            ) {
                self.style = style
                self.title = title
                self.enabled = enabled
                self.working = working
                self.checkingStatus = checkingStatus
                self.accessibilityId = accessibilityId
            }
        }
    }

    public enum Path: Equatable, Sendable {
        case why, scopes, connected
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)
        case statusLoaded(connected: Bool, email: String?)
        case connectSucceeded(email: String?)
        case connectCancelled
        case disconnectSucceeded
        /// Error (or other) toast — `ToastClient` → feature `.evenToastHost()`.
        case presentToast(Toast)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case primaryTapped
            case secondaryTapped
            case backTapped
            case disconnectTapped
        }

        @CasePathable
        public enum Delegate: Equatable {
            case finished
        }
    }

    @Dependency(\.googleClient) var googleClient
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.toastClient) var toastClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .view(.appear):
                if EvenLaunchArguments.skipGooglePrompt {
                    return .send(.view(.secondaryTapped))
                }
                state.isCheckingStatus = true
                return .run { [googleClient] send in
                    do {
                        let status = try await googleClient.status()
                        await send(.statusLoaded(connected: status.connected, email: status.email))
                    } catch {
                        await send(.presentToast(.googleFailure(error)))
                    }
                }

            case let .statusLoaded(connected, email):
                state.isCheckingStatus = false
                state.email = email
                if connected { state.path = .connected }
                return .none

            case .view(.primaryTapped):
                switch state.path {
                case .why:
                    guard !state.isBusy else { return .none }
                    state.working = true
                    return .run { [googleClient] send in
                        do {
                            try await googleClient.connect()
                            let status = try await googleClient.status()
                            await send(.connectSucceeded(email: status.email))
                        } catch {
                            if Self.isUserCancellation(error) {
                                await send(.connectCancelled)
                            } else {
                                await send(.presentToast(.googleFailure(error)))
                            }
                        }
                    }
                case .scopes:
                    guard state.canAllowScopes else { return .none }
                    state.path = .connected
                    return .none
                case .connected:
                    return finishWithNotificationPrompt()
                }

            case let .connectSucceeded(email):
                state.working = false
                state.email = email
                state.path = .scopes
                return toastEffect(.init(message: "Google connected", tone: .success))

            case .connectCancelled:
                state.working = false
                return .none

            case .view(.secondaryTapped):
                guard state.footer.secondary != nil else { return .none }
                switch state.path {
                case .why:
                    guard !state.isBusy else { return .none }
                    return .merge(
                        toastEffect(.init(message: "Skipped for now")),
                        finishWithNotificationPrompt()
                    )
                case .scopes, .connected:
                    return .none
                }

            case .view(.backTapped):
                state.path = .why
                return .none

            case .view(.disconnectTapped):
                guard !state.working else { return .none }
                state.working = true
                return .run { [googleClient] send in
                    do {
                        try await googleClient.disconnect()
                        await send(.disconnectSucceeded)
                    } catch {
                        await send(.presentToast(.googleFailure(error)))
                    }
                }

            case .disconnectSucceeded:
                state.working = false
                state.email = nil
                state.gmailEnabled = true
                state.calendarEnabled = true
                state.path = .why
                return toastEffect(.init(message: "Google disconnected"))

            case let .presentToast(toast):
                if toast.tone == .error {
                    state.working = false
                    state.isCheckingStatus = false
                }
                return toastEffect(toast)

            case .delegate:
                return .none
            }
        }
    }

    /// Delivers a toast to `ToastClient` → nearest `.evenToastHost()` overlay.
    private func toastEffect(_ toast: Toast) -> Effect<Action> {
        .run { [toastClient] _ in
            await toastClient.show(toast)
        }
    }

    private func finishWithNotificationPrompt() -> Effect<Action> {
        .run { [notificationsClient] send in
            _ = await notificationsClient.requestAuthorization()
            await send(.delegate(.finished))
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == URLError.cancelled.rawValue { return true }
        if ns.domain == NSURLErrorDomain, ns.code == URLError.userCancelledAuthentication.rawValue {
            return true
        }
        return false
    }
}

extension Toast {
    /// Google-facing copy lives with the feature that talks to Google — the
    /// toast module has no business naming a provider.
    static func googleFailure(_ error: Error) -> Toast {
        .failure(
            from: error,
            offline: "Couldn’t reach Google",
            fallback: "Google connection failed"
        )
    }
}

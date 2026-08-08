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
        /// The partner's Gmail is theirs alone — all we ever learn is whether
        /// they have one, so we can explain the already-live shared calendar.
        public var partnerConnected = false
        public var working = false
        public var isCheckingStatus = false
        public var gmailEnabled = true
        public var calendarEnabled = true
        /// The household's shared calendar and where the caller stands on it:
        /// owner, already listed, or offered the one-tap add. Nil until the
        /// caller has their own connection (the endpoint needs one).
        public var calendar: GoogleCalendarInfo?
        /// The add confirm is in flight — the card shows its own busy state
        /// rather than blocking the shell footer.
        public var addingCalendar = false
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
        case statusLoaded(connected: Bool, email: String?, partnerConnected: Bool)
        case connectSucceeded(email: String?, partnerConnected: Bool)
        case connectCancelled
        case disconnectSucceeded
        case calendarInfoLoaded(GoogleCalendarInfo)
        case calendarAdded(GoogleCalendarAddResult)
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
            /// "Add Even calendar to my Google" — the partner's confirm.
            case addCalendarTapped
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
                        await send(.statusLoaded(
                            connected: status.connected,
                            email: status.email,
                            partnerConnected: status.hasPartnerConnected
                        ))
                    } catch {
                        await send(.presentToast(.googleFailure(error)))
                    }
                }

            case let .statusLoaded(connected, email, partnerConnected):
                state.isCheckingStatus = false
                state.email = email
                state.partnerConnected = partnerConnected
                // Only the caller's own connection opens the success screen. A
                // partner who joined by invite code lands on `.why` with their
                // own connect flow, never on someone else's "connected".
                state.path = connected ? .connected : .why
                guard connected else {
                    state.calendar = nil
                    return .none
                }
                return loadCalendarInfo()

            case .view(.primaryTapped):
                switch state.path {
                case .why:
                    guard !state.isBusy else { return .none }
                    state.working = true
                    return .run { [googleClient] send in
                        do {
                            try await googleClient.connect()
                            let status = try await googleClient.status()
                            await send(.connectSucceeded(
                                email: status.email,
                                partnerConnected: status.hasPartnerConnected
                            ))
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

            case let .connectSucceeded(email, partnerConnected):
                state.working = false
                state.email = email
                state.partnerConnected = partnerConnected
                state.path = .scopes
                return .merge(
                    toastEffect(.init(message: "Google connected", tone: .success)),
                    loadCalendarInfo()
                )

            case let .calendarInfoLoaded(info):
                state.calendar = info
                return .none

            case .view(.addCalendarTapped):
                // Only offer what the server says it can fulfil — a stale
                // build must never claim a share it cannot perform.
                guard state.calendar?.offersAdd == true, !state.addingCalendar else { return .none }
                state.addingCalendar = true
                return .run { [googleClient] send in
                    do {
                        let result = try await googleClient.addSharedCalendar()
                        await send(.calendarAdded(result))
                    } catch {
                        await send(.presentToast(.calendarAddFailure(error)))
                    }
                }

            case let .calendarAdded(result):
                state.addingCalendar = false
                state.calendar = GoogleCalendarInfo(
                    calendarId: result.calendarId,
                    shared: true,
                    shareUrl: state.calendar?.shareUrl,
                    owner: result.owner ?? false,
                    listed: result.listed,
                    canAdd: false
                )
                return toastEffect(.init(message: "On your Google Calendar", tone: .success))

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
                state.calendar = nil
                state.path = .why
                return toastEffect(.init(message: "Google disconnected"))

            case let .presentToast(toast):
                if toast.tone == .error {
                    state.working = false
                    state.isCheckingStatus = false
                    state.addingCalendar = false
                }
                return toastEffect(toast)

            case .delegate:
                return .none
            }
        }
    }

    /// Reads the shared calendar's state for this member. A failure here is
    /// quiet on purpose: the screen still works, the confirm simply stays
    /// hidden until we know it applies.
    private func loadCalendarInfo() -> Effect<Action> {
        .run { [googleClient] send in
            if let info = try? await googleClient.calendarInfo() {
                await send(.calendarInfoLoaded(info))
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

    /// A share that did not happen must never read as success — the copy sends
    /// the user back to Google rather than claiming the calendar is theirs.
    static func calendarAddFailure(_ error: Error) -> Toast {
        .failure(
            from: error,
            offline: "Couldn’t reach Google",
            fallback: "Couldn’t add the calendar — reconnect Google and try again"
        )
    }
}

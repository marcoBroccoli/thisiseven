import AuthClient
import CalendarClient
import ComposableArchitecture
import DraftsClient
import EvenCore
import GoogleClient
import HouseholdClient
import LoginFeature
import NotificationsClient
import OnboardingFeature
import SummaryClient
import TasksClient
import WidgetClient

public enum EvenAppPreviewSupport {
    /// Boot → login → onboarding → household → connections → ready.
    public static func flow() -> StoreOf<AppReducer> {
        Store(initialState: .booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .signedOut }
            $0.authClient.signInWithApple = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
            $0.authClient.signInEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
            $0.authClient.signUpEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }

            $0.householdClient.create = { _, _ in PreviewData.household }
            $0.householdClient.join = { _, _ in PreviewData.household }

            $0.googleClient.status = { PreviewData.googleDisconnected }
            $0.googleClient.connect = {}
            $0.notificationsClient.requestAuthorization = { true }

            $0.summaryClient.fetch = { PreviewData.summary }
            $0.tasksClient.toggle = { _ in PreviewData.laundry }
            $0.tasksClient.create = { _ in PreviewData.laundry }
            $0.widgetClient.publish = { _ in }
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
        }
    }

    public static func booting() -> StoreOf<AppReducer> {
        Store(initialState: .booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return .signedOut
            }
        }
    }

    public static func login() -> StoreOf<AppReducer> {
        Store(initialState: .login(LoginReducer.State())) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .signedOut }
            $0.authClient.signInWithApple = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
            $0.authClient.signInEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
            $0.authClient.signUpEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
        }
    }

    public static func onboarding() -> StoreOf<AppReducer> {
        Store(initialState: .onboarding(.weigh)) {
            AppReducer()
        }
    }

    public static func ready() -> StoreOf<AppReducer> {
        Store(initialState: .ready(MainTabReducer.State())) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .ready }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.widgetClient.publish = { _ in }
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
        }
    }
}

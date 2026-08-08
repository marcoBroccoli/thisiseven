import ComposableArchitecture
import ConnectionsFeature
import Design
import EvenCore
import Foundation
import GoogleClient
import NotificationsClient
import ToastClient
import XCTest

@MainActor
final class ConnectionsFeatureTests: XCTestCase {
    func testSkipFinishesAfterNotificationPrompt() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.notificationsClient.requestAuthorization = { true }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.secondaryTapped))
        await store.receive(\.delegate.finished)
    }

    func testAppearChecksStatus() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googleDisconnected }
        }

        await store.send(.view(.appear)) {
            $0.isCheckingStatus = true
        }
        await store.receive(\.statusLoaded) {
            $0.isCheckingStatus = false
        }
    }

    func testAppearAlreadyConnectedJumpsToConnected() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googleConnected }
            $0.googleClient.calendarInfo = { PreviewData.calendarInfoCanAdd }
        }

        await store.send(.view(.appear)) {
            $0.isCheckingStatus = true
        }
        await store.receive(\.statusLoaded) {
            $0.isCheckingStatus = false
            $0.email = PreviewData.googleConnected.email
            $0.path = .connected
        }
        await store.receive(\.calendarInfoLoaded) {
            $0.calendar = PreviewData.calendarInfoCanAdd
        }
    }

    /// The partner's confirm: reader ACL + CalendarList happen server-side;
    /// the app only has to stop offering the add once it lands.
    func testAddSharedCalendarMarksItListed() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email
        state.calendar = PreviewData.calendarInfoCanAdd

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.addSharedCalendar = { PreviewData.calendarAdded }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.addCalendarTapped)) {
            $0.addingCalendar = true
        }
        await store.receive(\.calendarAdded) {
            $0.addingCalendar = false
            $0.calendar = GoogleCalendarInfo(
                calendarId: PreviewData.calendarAdded.calendarId,
                shared: true,
                shareUrl: PreviewData.calendarInfoCanAdd.shareUrl,
                owner: false,
                listed: true,
                canAdd: false
            )
        }
        XCTAssertFalse(store.state.calendar?.offersAdd ?? true, "the confirm must not be offered twice")
    }

    /// A share that Google refused (stale scope, offline) must land as an
    /// error toast — never as a calendar the member does not actually have.
    func testAddSharedCalendarFailureKeepsOffer() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.calendar = PreviewData.calendarInfoCanAdd

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.addSharedCalendar = { throw URLError(.notConnectedToInternet) }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.addCalendarTapped)) {
            $0.addingCalendar = true
        }
        await store.receive(\.presentToast) {
            $0.addingCalendar = false
        }
        XCTAssertTrue(store.state.calendar?.offersAdd ?? false, "a failed add keeps the confirm available")
        XCTAssertFalse(store.state.calendar?.isListed ?? true, "a failed add must not claim success")
    }

    /// The member whose Google hosts the calendar is never shown the confirm,
    /// and tapping it (stale UI) does nothing.
    func testOwnerIsNeverOfferedTheAdd() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.calendar = PreviewData.calendarInfoOwner

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.addSharedCalendar = {
                XCTFail("the owner must never call calendar/add")
                return PreviewData.calendarAdded
            }
        }

        await store.send(.view(.addCalendarTapped))
        XCTAssertFalse(store.state.addingCalendar)
    }

    /// Disconnecting drops the calendar standing with the connection — the
    /// next member to connect gets their own answer from the server.
    func testDisconnectClearsCalendarState() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email
        state.calendar = PreviewData.calendarInfoListed

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.disconnect = {}
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.disconnectTapped)) {
            $0.working = true
        }
        await store.receive(\.disconnectSucceeded) {
            $0.working = false
            $0.email = nil
            $0.calendar = nil
            $0.path = .why
        }
    }

    /// The real bug: a partner who joined by invite code used to inherit the
    /// other member's household-wide connection and land on their success
    /// screen. Their own status is what decides the screen now.
    func testJoinedPartnerSeesOwnNotConnectedState() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googlePartnerConnectedOnly }
        }

        await store.send(.view(.appear)) {
            $0.isCheckingStatus = true
        }
        await store.receive(\.statusLoaded) {
            $0.isCheckingStatus = false
            $0.partnerConnected = true
            $0.path = .why
        }
        XCTAssertNil(store.state.email, "the partner's address must never reach this member")
    }

    /// A member who disconnects returns to their own connect flow while the
    /// partner's connection — and the shared calendar — are untouched.
    func testDisconnectKeepsPartnerConnectionKnown() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email
        state.partnerConnected = true

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.disconnect = {}
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.disconnectTapped)) {
            $0.working = true
        }
        await store.receive(\.disconnectSucceeded) {
            $0.working = false
            $0.email = nil
            $0.path = .why
        }
        XCTAssertTrue(store.state.partnerConnected)
    }

    func testConnectAdvancesToScopes() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = {}
            $0.googleClient.status = { PreviewData.googleConnected }
            $0.googleClient.calendarInfo = { PreviewData.calendarInfoNotReady }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.primaryTapped)) {
            $0.working = true
        }
        await store.receive(\.connectSucceeded) {
            $0.working = false
            $0.email = PreviewData.googleConnected.email
            $0.path = .scopes
        }
        // Connecting also asks where this member stands on the shared calendar.
        await store.receive(\.calendarInfoLoaded) {
            $0.calendar = PreviewData.calendarInfoNotReady
        }
    }

    func testConnectFailurePresentsErrorToast() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = { throw URLError(.notConnectedToInternet) }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.primaryTapped)) {
            $0.working = true
        }
        await store.receive(\.presentToast) {
            $0.working = false
            $0.isCheckingStatus = false
        }
    }

    func testConnectCancelIsQuiet() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = { throw CancellationError() }
        }

        await store.send(.view(.primaryTapped)) {
            $0.working = true
        }
        await store.receive(\.connectCancelled) {
            $0.working = false
        }
    }

    func testAllowScopesThenGoToEvenFinishes() async {
        var state = ConnectionsReducer.State()
        state.path = .scopes
        state.email = PreviewData.googleConnected.email

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.notificationsClient.requestAuthorization = { true }
        }

        await store.send(.view(.primaryTapped)) {
            $0.path = .connected
        }
        await store.send(.view(.primaryTapped))
        await store.receive(\.delegate.finished)
    }

    func testDisconnectReturnsToWhy() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.disconnect = {}
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.disconnectTapped)) {
            $0.working = true
        }
        await store.receive(\.disconnectSucceeded) {
            $0.working = false
            $0.email = nil
            $0.path = .why
        }
    }
}

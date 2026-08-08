import AuthClient
import ComposableArchitecture
import EvenApp
import EvenCore
import HouseholdRealtimeClient
import SummaryClient
import WidgetClient
import XCTest

@MainActor
final class MainTabReducerTests: XCTestCase {
    func testRealtimeSummaryInvalidateRefreshesToday() async {
        let (stream, continuation) = AsyncStream.makeStream(of: HouseholdRealtimeEvent.self)
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.summary = PreviewData.summary
        state.today.isLoading = false

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.householdRealtimeClient.events = { stream }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.widgetClient.publish = { _ in }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            // Mid-week clock: these cases are about realtime, not the ritual.
            $0.date = .constant(Self.wednesday)
            $0.calendar = gregorianUTC()
            $0.defaultAppStorage = suite()
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        continuation.yield(
            HouseholdRealtimeEvent(
                scopes: ["summary"],
                reason: "task_toggled",
                actorMemberId: PreviewData.umut.id
            )
        )
        await store.receive(\.realtime)
        await store.receive(\.today.view.refresh)
        await store.receive(\.today.summaryLoaded)
        continuation.finish()
        await store.finish()
    }

    func testRealtimeFromSelfSkipsTodayRefresh() async {
        let (stream, continuation) = AsyncStream.makeStream(of: HouseholdRealtimeEvent.self)
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.summary = PreviewData.summary
        state.today.isLoading = false
        let fetched = LockIsolated(0)

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.householdRealtimeClient.events = { stream }
            $0.summaryClient.fetch = {
                fetched.withValue { $0 += 1 }
                return PreviewData.summary
            }
            $0.widgetClient.publish = { _ in }
            $0.date = .constant(Self.wednesday)
            $0.calendar = gregorianUTC()
            $0.defaultAppStorage = suite()
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        continuation.yield(
            HouseholdRealtimeEvent(
                scopes: ["summary"],
                reason: "task_toggled",
                actorMemberId: PreviewData.ada.id
            )
        )
        await store.receive(\.realtime)
        continuation.finish()
        await store.finish()
        XCTAssertEqual(fetched.value, 0)
    }

    func testSelectProfileTab() async {
        let store = TestStore(initialState: MainTabReducer.State()) {
            MainTabReducer()
        } withDependencies: {
            $0.defaultAppStorage = suite()
        }
        await store.send(.view(.selectTab(.profile))) {
            $0.tab = .profile
        }
    }

    // MARK: - The Sunday ritual trigger

    /// 2026-08-09 is a Sunday; 2026-08-05 a Wednesday.
    private static let sunday = Date(timeIntervalSince1970: 1_786_233_600)
    private static let wednesday = Date(timeIntervalSince1970: 1_785_888_000)

    private func summary(startedOn: String) -> Summary {
        var summary = PreviewData.summary
        summary.week = Week(
            id: PreviewData.weekId, index: summary.week.index, startedOn: startedOn
        )
        return summary
    }

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A fresh defaults suite per test so `@Shared(.appStorage)` never leaks
    /// a poured week between cases.
    private func suite(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: name)!
    }

    func testIsResetDueOnSunday() {
        XCTAssertTrue(MainTabReducer.isResetDue(
            weekStartedOn: "2026-08-03", now: Self.sunday, calendar: gregorianUTC()
        ))
    }

    func testIsResetDueForAnOverdueWeekOnAnyDay() {
        // Week 1 has been open since July — it must ask on the next launch.
        XCTAssertTrue(MainTabReducer.isResetDue(
            weekStartedOn: "2026-07-17", now: Self.wednesday, calendar: gregorianUTC()
        ))
    }

    func testIsNotResetDueMidWeek() {
        XCTAssertFalse(MainTabReducer.isResetDue(
            weekStartedOn: "2026-08-03", now: Self.wednesday, calendar: gregorianUTC()
        ))
    }

    func testSummaryOnSundayPresentsTheRitual() async {
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.partner = PreviewData.umut
        let loaded = summary(startedOn: "2026-08-03")

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.date = .constant(Self.sunday)
            $0.calendar = gregorianUTC()
            $0.widgetClient.publish = { _ in }
            $0.defaultAppStorage = suite()
        }
        store.exhaustivity = .off

        await store.send(.today(.summaryLoaded(loaded)))
        XCTAssertNotNil(store.state.reset)
        XCTAssertEqual(store.state.reset?.partner, PreviewData.umut)
    }

    func testMidWeekSummaryDoesNotPresentTheRitual() async {
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.date = .constant(Self.wednesday)
            $0.calendar = gregorianUTC()
            $0.widgetClient.publish = { _ in }
            $0.defaultAppStorage = suite()
        }
        store.exhaustivity = .off

        await store.send(.today(.summaryLoaded(summary(startedOn: "2026-08-03"))))
        XCTAssertNil(store.state.reset)
    }

    func testDismissingTheRitualLetsItReturnOnTheNextAppear() async {
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.partner = PreviewData.umut
        let loaded = summary(startedOn: "2026-08-03")

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.date = .constant(Self.sunday)
            $0.calendar = gregorianUTC()
            $0.householdRealtimeClient.events = { AsyncStream { _ in } }
            $0.widgetClient.publish = { _ in }
            $0.defaultAppStorage = suite()
        }
        store.exhaustivity = .off

        await store.send(.today(.summaryLoaded(loaded)))
        XCTAssertNotNil(store.state.reset)

        await store.send(.reset(.presented(.delegate(.dismissed))))
        XCTAssertNil(store.state.reset)

        // Still dismissed while the app stays where it is…
        await store.send(.today(.summaryLoaded(loaded)))
        XCTAssertNil(store.state.reset)

        // …but "later today" does not survive coming back to the app.
        await store.send(.view(.appear))
        await store.send(.today(.summaryLoaded(loaded)))
        XCTAssertNotNil(store.state.reset)

        await store.send(.view(.selectTab(.today)))
        await store.finish()
    }

    func testAPouredWeekNeverAsksAgain() async {
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.partner = PreviewData.umut
        let loaded = summary(startedOn: "2026-08-03")

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.date = .constant(Self.sunday)
            $0.calendar = gregorianUTC()
            $0.summaryClient.fetch = { loaded }
            $0.widgetClient.publish = { _ in }
            $0.householdRealtimeClient.events = { AsyncStream { _ in } }
            $0.defaultAppStorage = suite()
        }
        store.exhaustivity = .off

        await store.send(.today(.summaryLoaded(loaded)))
        XCTAssertNotNil(store.state.reset)

        await store.send(.reset(.presented(.delegate(.poured(
            closedWeekID: PreviewData.weekId, newWeek: PreviewData.weekClose.newWeek
        )))))
        XCTAssertEqual(store.state.lastPouredWeekID, PreviewData.weekId.uuidString)

        // Close the sheet, then let Today reload the same (stale) week — it
        // must not ask to be poured a second time.
        await store.send(.reset(.presented(.delegate(.dismissed))))
        await store.send(.view(.appear))
        await store.send(.today(.summaryLoaded(loaded)))
        XCTAssertNil(store.state.reset)
        await store.finish()
    }
}

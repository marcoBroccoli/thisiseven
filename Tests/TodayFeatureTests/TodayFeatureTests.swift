import AuthClient
import ComposableArchitecture
import EvenCore
import SummaryClient
import TasksClient
import ToastClient
import ToastUI
import TodayFeature
import WidgetClient
import XCTest

@MainActor
final class TodayFeatureTests: XCTestCase {
    func testAppearLoadsSummaryAndMembers() async {
        let store = TestStore(initialState: TodayReducer.State()) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.summary = PreviewData.summary
        }
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.me, PreviewData.ada)
        XCTAssertEqual(store.state.partner, PreviewData.umut)
    }

    func testAppearWithExistingSummaryDoesNotFlashLoading() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.isLoading = false

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        await store.receive(\.summaryLoaded) {
            $0.summary = PreviewData.summary
        }
        XCTAssertFalse(store.state.isLoading)
    }

    func testOrganizeModeFlipsWithoutRefetch() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.isLoading = false
        XCTAssertEqual(state.organizeMode, .day)

        let fetched = LockIsolated(0)
        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = {
                fetched.withValue { $0 += 1 }
                return PreviewData.summary
            }
        }
        store.exhaustivity = .off

        await store.send(.view(.organize(.type))) {
            $0.organizeMode = .type
        }
        await store.send(.view(.organize(.person))) {
            $0.organizeMode = .person
        }
        await store.finish()
        XCTAssertEqual(fetched.value, 0)
        XCTAssertEqual(store.state.summary, PreviewData.summary)
    }

    func testToggleAppliesLocallyWithoutWaitingForRefresh() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        let id = PreviewData.laundry.id
        let toggled = LockIsolated(false)

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.toggle = { _ in
                toggled.setValue(true)
                return PreviewData.laundry
            }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.toggle(id))) {
            var summary = PreviewData.summary
            var task = PreviewData.laundry
            task.done = true
            task.doneByMemberId = task.ownerMemberId
            summary.applyToggleResult(
                task,
                meId: PreviewData.ada.id,
                meName: PreviewData.ada.displayName,
                partnerId: PreviewData.umut.id,
                partnerName: PreviewData.umut.displayName
            )
            $0.summary = summary
        }
        await store.finish()
        XCTAssertTrue(toggled.value)
        XCTAssertEqual(
            store.state.summary?.pebbles.last?.memberId,
            PreviewData.laundry.ownerMemberId
        )
        XCTAssertEqual(store.state.summary?.pebbles.last?.weight, PreviewData.laundry.weight)
    }

    func testToggleFailureToastsAndRefreshes() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        let id = PreviewData.laundry.id
        let toasted = LockIsolated<Toast.Tone?>(nil)

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.toggle = { _ in throw URLError(.timedOut) }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.tone)
            }
        }
        store.exhaustivity = .off

        await store.send(.view(.toggle(id))) {
            var summary = PreviewData.summary
            var task = PreviewData.laundry
            task.done = true
            task.doneByMemberId = task.ownerMemberId
            summary.applyToggleResult(
                task,
                meId: PreviewData.ada.id,
                meName: PreviewData.ada.displayName,
                partnerId: PreviewData.umut.id,
                partnerName: PreviewData.umut.displayName
            )
            $0.summary = summary
        }
        await store.receive(\.presentToast)
        await store.receive(\.view.refresh)
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.summary = PreviewData.summary
        }
        XCTAssertEqual(toasted.value, .error)
    }

    func testRefreshWhenEmptyShowsLoading() async {
        var state = TodayReducer.State()
        state.isLoading = false
        state.summary = nil

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.refresh)) {
            $0.isLoading = true
        }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.summary = PreviewData.summary
        }
    }

    func testLoadFailureClearsLoadingAndToasts() async {
        let toasted = LockIsolated<Toast.Tone?>(nil)

        let store = TestStore(initialState: TodayReducer.State()) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = { throw URLError(.notConnectedToInternet) }
            $0.authClient.householdMembers = { (nil, nil) }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.tone)
            }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        await store.receive(\.presentToast) {
            $0.isLoading = false
        }
        XCTAssertEqual(toasted.value, .error)
    }

    func testAddTappedPresentsComposer() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.isLoading = false

        let store = TestStore(initialState: state) {
            TodayReducer()
        }

        await store.send(.view(.addTapped)) {
            $0.composer = ComposerReducer.State()
        }
    }

    func testCreateTaskOptimisticWithoutRefreshOnSuccess() async throws {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        var composer = ComposerReducer.State()
        composer.title = "Walk the dog"
        composer.weight = 2
        state.composer = composer
        let createdId = try XCTUnwrap(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
        let created = PreviewData.task(
            id: createdId,
            title: "Walk the dog",
            weight: 2,
            meta: "TODAY · ONE-OFF"
        )
        let toasted = LockIsolated<String?>(nil)
        let refreshed = LockIsolated(false)
        let baselineCount = PreviewData.summary.sections.flatMap(\.tasks).count

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { _ in created }
            $0.summaryClient.fetch = {
                refreshed.setValue(true)
                return PreviewData.summary
            }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.message)
            }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask) {
            $0.composer = nil
        }
        XCTAssertEqual(
            store.state.summary?.sections.flatMap(\.tasks).count,
            baselineCount + 1
        )
        XCTAssertTrue(
            store.state.summary?.sections.flatMap(\.tasks).contains { $0.title == "Walk the dog" } ?? false
        )

        await store.receive(\.createSucceeded)
        await store.finish()
        XCTAssertEqual(toasted.value, "Added to Today")
        XCTAssertFalse(refreshed.value)
        XCTAssertEqual(
            store.state.summary?.sections.flatMap(\.tasks).first(where: { $0.title == "Walk the dog" })?.id,
            createdId
        )
    }

    func testCreateOptimisticTaskReflectsComposerFields() async throws {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        var composer = ComposerReducer.State()
        composer.title = "Pay insurance"
        composer.section = .admin
        composer.recurrence = .weekly
        composer.dueOption = .tomorrow
        composer.weight = 3
        composer.ownerIsMe = false
        state.composer = composer

        let expectedDue = ComposerReducer.DueOption.tomorrow.dueOnISO()
        let expectedMeta = HouseholdTask.makeMetaLine(dueOn: expectedDue, recurrence: .weekly)
        XCTAssertEqual(expectedMeta, "TOMORROW · WEEKLY")
        let createdId = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let created = HouseholdTask(
            id: createdId,
            title: "Pay insurance",
            section: .admin,
            ownerMemberId: PreviewData.umut.id,
            weight: 3,
            recurrence: .weekly,
            dueOn: expectedDue,
            done: false,
            metaLine: expectedMeta
        )

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { body in
                XCTAssertEqual(body.section, .admin)
                XCTAssertEqual(body.recurrence, .weekly)
                XCTAssertEqual(body.dueOn, expectedDue)
                XCTAssertEqual(body.weight, 3)
                XCTAssertEqual(body.ownerMemberId, PreviewData.umut.id)
                return created
            }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask) {
            $0.composer = nil
        }

        let optimistic = store.state.summary?.sections
            .first(where: { $0.key == .admin })?
            .tasks
            .first(where: { $0.title == "Pay insurance" })
        XCTAssertEqual(optimistic?.section, .admin)
        XCTAssertEqual(optimistic?.recurrence, .weekly)
        XCTAssertEqual(optimistic?.dueOn, expectedDue)
        XCTAssertEqual(optimistic?.weight, 3)
        XCTAssertEqual(optimistic?.ownerMemberId, PreviewData.umut.id)
        XCTAssertEqual(optimistic?.metaLine, expectedMeta)
        XCTAssertEqual(optimistic?.resolvedMetaLine, "TOMORROW · WEEKLY")
        XCTAssertNotEqual(optimistic?.metaLine, "WEEKLY")

        await store.receive(\.createSucceeded)
        await store.finish()

        let swapped = store.state.summary?.sections
            .first(where: { $0.key == .admin })?
            .tasks
            .first(where: { $0.title == "Pay insurance" })
        XCTAssertEqual(swapped?.id, createdId)
        XCTAssertEqual(swapped?.dueOn, expectedDue)
        XCTAssertEqual(swapped?.metaLine, expectedMeta)
        XCTAssertEqual(swapped?.resolvedMetaLine, "TOMORROW · WEEKLY")
        XCTAssertEqual(swapped?.section, .admin)
        XCTAssertEqual(swapped?.recurrence, .weekly)
    }

    /// A repeat bounded by a count must read the same before and after the POST
    /// lands: the client derives the same end date the server does.
    func testCreateCarriesTheRepeatCountAndDerivesItsEnd() async throws {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        var composer = ComposerReducer.State()
        composer.title = "Water the plants"
        composer.recurrence = .weekly
        composer.dueOption = .tomorrow
        composer.endOption = .afterCount
        composer.endCount = 6
        state.composer = composer

        let calendar = Calendar.evenHousehold
        let expectedDue = ComposerReducer.DueOption.tomorrow.dueOnISO()
        let expectedUntil = try calendar.evenCivilDateString(
            from: XCTUnwrap(try Recurrence.weekly.recurrenceEnd(
                anchor: XCTUnwrap(try calendar.evenParseCivilDate(XCTUnwrap(expectedDue))), count: 6
            ))
        )

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { body in
                XCTAssertEqual(body.recurrenceCount, 6)
                // Only one spelling of the bound goes over the wire.
                XCTAssertNil(body.recurrenceUntil)
                throw URLError(.timedOut)
            }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { _ in }
            $0.summaryClient.fetch = { PreviewData.summary }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask)

        let optimistic = store.state.summary?.sections
            .flatMap(\.tasks)
            .first { $0.title == "Water the plants" }
        XCTAssertEqual(optimistic?.recurrenceCount, 6)
        XCTAssertEqual(optimistic?.recurrenceUntil, expectedUntil)
        XCTAssertEqual(optimistic?.metaLine, "TOMORROW · WEEKLY · 6 TIMES")
        XCTAssertEqual(optimistic?.resolvedMetaLine, "TOMORROW · WEEKLY · 6 TIMES")

        await store.finish()
    }

    func testCreateCarriesTheRepeatEndDate() async throws {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        let calendar = Calendar.evenHousehold
        let endDate = try XCTUnwrap(calendar.evenParseCivilDate("2026-12-24"))
        var composer = ComposerReducer.State()
        composer.title = "Water the plants"
        composer.recurrence = .weekly
        composer.endOption = .onDate
        composer.endDate = endDate
        state.composer = composer

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { body in
                XCTAssertEqual(body.recurrenceUntil, "2026-12-24")
                XCTAssertNil(body.recurrenceCount)
                throw URLError(.timedOut)
            }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { _ in }
            $0.summaryClient.fetch = { PreviewData.summary }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask)

        let optimistic = store.state.summary?.sections
            .flatMap(\.tasks)
            .first { $0.title == "Water the plants" }
        XCTAssertEqual(optimistic?.recurrenceUntil, "2026-12-24")
        XCTAssertNil(optimistic?.recurrenceCount)
        XCTAssertEqual(optimistic?.metaLine, "TODAY · WEEKLY · UNTIL DEC 24")

        await store.finish()
    }

    /// A one-off has no series, so it must never carry a bound — the API rejects
    /// that combination with `bad_recurrence_end`.
    func testComposerDropsTheRepeatEndWhenGoingBackToOneOff() async {
        var composer = ComposerReducer.State()
        composer.recurrence = .weekly
        composer.endOption = .afterCount

        let store = TestStore(initialState: composer) {
            ComposerReducer()
        }

        XCTAssertTrue(store.state.showsRepeatEnd)
        await store.send(.view(.selectRecurrence(.none))) {
            $0.recurrence = .none
            $0.endOption = .never
        }
        XCTAssertFalse(store.state.showsRepeatEnd)
        let end = store.state.recurrenceEnd()
        XCTAssertNil(end.until)
        XCTAssertNil(end.count)
    }

    /// Moving the due date forward moves the first occurrence with it; an end
    /// date left behind it would describe an impossible series.
    func testComposerPullsAStaleEndDateForwardWithTheAnchor() async {
        let calendar = Calendar.evenHousehold
        var composer = ComposerReducer.State()
        composer.recurrence = .weekly
        composer.endOption = .onDate
        composer.dueOption = .today
        composer.endDate = calendar.startOfDay(for: Date())

        let store = TestStore(initialState: composer) {
            ComposerReducer()
        }
        store.exhaustivity = .off

        await store.send(.view(.selectDue(.tomorrow)))
        XCTAssertEqual(store.state.endDate, store.state.endDateRange.lowerBound)
        XCTAssertEqual(
            store.state.recurrenceEnd().until,
            ComposerReducer.DueOption.tomorrow.dueOnISO()
        )
    }

    /// Regression: API/preview returns weekly with nil `dueOn` + bare `WEEKLY`
    /// meta — createSucceeded must keep the optimistic due day and recompute.
    func testCreateSucceededKeepsLocalDueWhenAPIOmitsDueOn() async throws {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        var composer = ComposerReducer.State()
        composer.title = "Pay insurance"
        composer.section = .admin
        composer.recurrence = .weekly
        composer.dueOption = .tomorrow
        composer.weight = 2
        composer.ownerIsMe = true
        state.composer = composer

        let expectedDue = ComposerReducer.DueOption.tomorrow.dueOnISO()
        let expectedMeta = HouseholdTask.makeMetaLine(dueOn: expectedDue, recurrence: .weekly)
        XCTAssertEqual(expectedMeta, "TOMORROW · WEEKLY")
        let createdId = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let createdMissingDue = HouseholdTask(
            id: createdId,
            title: "Pay insurance",
            section: .admin,
            ownerMemberId: PreviewData.ada.id,
            weight: 2,
            recurrence: .weekly,
            dueOn: nil,
            done: false,
            metaLine: "WEEKLY"
        )

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { _ in createdMissingDue }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask)

        let optimistic = store.state.summary?.sections
            .flatMap(\.tasks)
            .first(where: { $0.title == "Pay insurance" })
        XCTAssertEqual(optimistic?.metaLine, expectedMeta)

        await store.receive(\.createSucceeded)
        await store.finish()

        let swapped = store.state.summary?.sections
            .flatMap(\.tasks)
            .first(where: { $0.title == "Pay insurance" })
        XCTAssertEqual(swapped?.id, createdId)
        XCTAssertEqual(swapped?.dueOn, expectedDue)
        XCTAssertEqual(swapped?.metaLine, expectedMeta)
        XCTAssertEqual(swapped?.resolvedMetaLine, "TOMORROW · WEEKLY")
        XCTAssertNotEqual(swapped?.metaLine, "WEEKLY")
    }

    /// Composer `.tomorrow` must emit civil tomorrow in Amsterdam — not the
    /// previous UTC day from `ISO8601DateFormatter`'s GMT default.
    func testComposerTomorrowDueOnISOLabelsTomorrowNotToday() throws {
        let calendar = Calendar.evenHousehold
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 15)))
        let dueOn = ComposerReducer.DueOption.tomorrow.dueOnISO(now: now)
        XCTAssertEqual(dueOn, "2026-08-08")
        XCTAssertEqual(
            HouseholdTask.makeMetaLine(dueOn: dueOn, recurrence: .none, now: now),
            "TOMORROW"
        )
    }

    func testCreateFailureToastsAndRefreshes() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        var composer = ComposerReducer.State()
        composer.title = "Walk the dog"
        state.composer = composer
        let toasted = LockIsolated<Toast.Tone?>(nil)

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { _ in throw URLError(.timedOut) }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.tone)
            }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask) {
            $0.composer = nil
        }
        XCTAssertEqual(
            store.state.summary?.sections.flatMap(\.tasks).count,
            PreviewData.summary.sections.flatMap(\.tasks).count + 1
        )
        await store.receive(\.presentToast)
        await store.receive(\.view.refresh)
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.summary = PreviewData.summary
        }
        XCTAssertEqual(toasted.value, .error)
        XCTAssertEqual(
            store.state.summary?.sections.flatMap(\.tasks).count,
            PreviewData.summary.sections.flatMap(\.tasks).count
        )
    }

    func testDeleteRemovesLocallyWithoutRefresh() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.isLoading = false
        let id = PreviewData.laundry.id
        let afterDelete: Summary = {
            var summary = PreviewData.summary
            summary.removingTask(id: id)
            return summary
        }()
        let deleted = LockIsolated(false)

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.delete = { _ in deleted.setValue(true) }
        }
        store.exhaustivity = .off

        await store.send(.view(.delete(id))) {
            $0.summary = afterDelete
        }
        await store.finish()
        XCTAssertTrue(deleted.value)
    }

    /// Hard rule: nothing done on either side → no pebble, and a level beam.
    /// Adding a task is not work done, so it must not touch the pans.
    func testCreateOnAnUntouchedWeekLeavesTheBeamEmptyAndLevel() async throws {
        var summary = PreviewData.summary
        summary.pebbles = []
        summary.sections = summary.sections.map { section in
            var next = section
            next.tasks = next.tasks.map {
                var task = $0
                task.done = false
                task.doneByMemberId = nil
                return task
            }
            return next
        }
        summary.recomputeShares(
            meId: PreviewData.ada.id,
            meName: PreviewData.ada.displayName,
            partnerId: PreviewData.umut.id,
            partnerName: PreviewData.umut.displayName
        )
        XCTAssertEqual(summary.caption, "Empty pans. A new week, level by definition")

        var state = TodayReducer.State()
        state.summary = summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        var composer = ComposerReducer.State()
        composer.title = "Walk the dog"
        composer.weight = 3
        state.composer = composer

        let createdId = try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"))
        let created = PreviewData.task(
            id: createdId,
            title: "Walk the dog",
            weight: 3,
            meta: "TODAY"
        )

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.create = { _ in created }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.createTask)
        XCTAssertEqual(store.state.summary?.pebbles, [])
        XCTAssertEqual(store.state.summary?.percentMe, 50)
        XCTAssertEqual(store.state.summary?.percentPartner, 50)

        await store.receive(\.createSucceeded)
        await store.finish()
        XCTAssertEqual(store.state.summary?.pebbles, [])
        XCTAssertEqual(store.state.summary?.percentMe, 50)
        XCTAssertEqual(store.state.summary?.percentPartner, 50)
        XCTAssertEqual(store.state.summary?.caption, "Empty pans. A new week, level by definition")
    }

    /// Regression: deleting a completed task left its pebble on the pan, so a
    /// week with nothing done still read "Leaning …" at 100/0.
    func testDeletingTheOnlyDoneTaskTakesItsPebbleOffTheBeam() async {
        var summary = PreviewData.summary
        summary.pebbles = [Pebble(memberId: PreviewData.ada.id, weight: PreviewData.trash.weight)]
        summary.sections = summary.sections.map { section in
            var next = section
            next.tasks = next.tasks.map { task in
                guard task.id != PreviewData.trash.id else { return task }
                var open = task
                open.done = false
                open.doneByMemberId = nil
                return open
            }
            return next
        }
        summary.recomputeShares(
            meId: PreviewData.ada.id,
            meName: PreviewData.ada.displayName,
            partnerId: PreviewData.umut.id,
            partnerName: PreviewData.umut.displayName
        )
        XCTAssertEqual(summary.percentMe, 100)

        var state = TodayReducer.State()
        state.summary = summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.delete = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.delete(PreviewData.trash.id)))
        await store.finish()

        XCTAssertFalse(
            store.state.summary?.sections.flatMap(\.tasks).contains { $0.done } ?? true
        )
        XCTAssertEqual(store.state.summary?.pebbles, [])
        XCTAssertEqual(store.state.summary?.percentMe, 50)
        XCTAssertEqual(store.state.summary?.percentPartner, 50)
        XCTAssertEqual(
            store.state.summary?.caption,
            "Empty pans. A new week, level by definition"
        )
    }

    /// Deleting open work must not disturb pebbles earned by other tasks.
    func testDeletingAnOpenTaskKeepsEarnedPebbles() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.delete = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.delete(PreviewData.laundry.id)))
        await store.finish()

        XCTAssertEqual(store.state.summary?.pebbles, PreviewData.summary.pebbles)
        XCTAssertEqual(store.state.summary?.percentMe, PreviewData.summary.percentMe)
    }

    /// A solo household with nothing done is level, not 100/0 — the client must
    /// not invent a lead the backend never reports (`summary.go` pctMe = 50).
    func testSoloHouseholdWithNothingDoneStaysLevel() {
        var summary = PreviewData.summary
        summary.pebbles = []
        summary.recomputeShares(
            meId: PreviewData.ada.id,
            meName: PreviewData.ada.displayName,
            partnerId: nil,
            partnerName: "Partner"
        )
        XCTAssertEqual(summary.percentMe, 50)
        XCTAssertEqual(summary.percentPartner, 50)
        XCTAssertEqual(summary.caption, "Empty pans. A new week, level by definition")
    }

    func testCancelDismissesComposer() async {
        var state = TodayReducer.State()
        state.composer = ComposerReducer.State()

        let store = TestStore(initialState: state) {
            TodayReducer()
        }

        await store.send(.composer(.presented(.view(.cancelTapped)))) {
            $0.composer = nil
        }
    }

    func testEditOpensComposerPrefillingTask() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        let task = PreviewData.laundry

        let store = TestStore(initialState: state) {
            TodayReducer()
        }

        await store.send(.view(.edit(task.id))) {
            $0.composer = ComposerReducer.State(editing: task, meId: PreviewData.ada.id)
        }
        XCTAssertEqual(store.state.composer?.title, task.title)
        XCTAssertEqual(store.state.composer?.editingTaskId, task.id)
        XCTAssertTrue(store.state.composer?.isEditing == true)
    }

    func testUpdateTaskOptimisticWithoutRefreshOnSuccess() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        let task = PreviewData.laundry
        state.composer = ComposerReducer.State(editing: task, meId: PreviewData.ada.id)
        state.composer?.title = "Fold laundry"
        state.composer?.weight = 3

        let updated = PreviewData.task(
            id: task.id,
            title: "Fold laundry",
            weight: 3,
            meta: task.metaLine
        )
        let toasted = LockIsolated<String?>(nil)
        let refreshed = LockIsolated(false)
        let patched = LockIsolated<EvenAPIClient.TaskDraftBody?>(nil)

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.update = { _, body in
                patched.setValue(body)
                return updated
            }
            $0.summaryClient.fetch = {
                refreshed.setValue(true)
                return PreviewData.summary
            }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.message)
            }
        }
        store.exhaustivity = .off

        await store.send(.composer(.presented(.view(.saveTapped))))
        await store.receive(\.updateTask) {
            $0.composer = nil
        }
        XCTAssertEqual(
            store.state.summary?.sections.flatMap(\.tasks).first(where: { $0.id == task.id })?.title,
            "Fold laundry"
        )
        XCTAssertEqual(
            store.state.summary?.sections.flatMap(\.tasks).first(where: { $0.id == task.id })?.weight,
            3
        )

        await store.receive(\.updateSucceeded)
        await store.finish()
        XCTAssertEqual(toasted.value, "Saved")
        XCTAssertFalse(refreshed.value)
        XCTAssertEqual(patched.value?.title, "Fold laundry")
        XCTAssertEqual(patched.value?.weight, 3)
    }
}

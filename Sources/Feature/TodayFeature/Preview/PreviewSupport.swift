import ComposableArchitecture
import EvenCore
import Foundation
import SummaryClient
import TasksClient
import ToastClient

public enum TodayPreviewSupport {
    public static let defaultLoadLag: Duration = .seconds(10)
    public static let defaultRefreshLag: Duration = .seconds(1)
    /// Short lag so canvas can paint before the failure toast.
    public static let defaultFailureLag: Duration = .milliseconds(400)

    public static func populated(
        refreshLag: Duration = defaultRefreshLag
    ) -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            let session = PreviewSummarySession(PreviewData.summary)
            $0.summaryClient.fetch = PreviewDelay.delayed(refreshLag) { session.summary }
            $0.tasksClient = session.tasksClient
            $0.toastClient = .silent()
        }
    }

    public static func empty(
        refreshLag: Duration = defaultRefreshLag
    ) -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summaryEmpty
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            let session = PreviewSummarySession(PreviewData.summaryEmpty)
            $0.summaryClient.fetch = PreviewDelay.delayed(refreshLag) { session.summary }
            $0.tasksClient = session.tasksClient
            $0.toastClient = .silent()
        }
    }

    /// Seeded skeleton — effects hang so loading chrome stays visible.
    public static func loading(
        loadLag: Duration = defaultLoadLag
    ) -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.isLoading = true
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = PreviewDelay.delayed(loadLag) { PreviewData.summary }
            $0.toastClient = .silent()
        }
    }

    /// Toggle throws → error toast via `.evenToastHost()`. Fire `.view(.toggle)` from the preview.
    public static func toggleFails() -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            let session = PreviewSummarySession(PreviewData.summary)
            $0.summaryClient.fetch = { session.summary }
            // Throw immediately — `Task.sleep` lags often never advance under RenderPreview.
            $0.tasksClient.toggle = { _ in throw URLError(.timedOut) }
            $0.toastClient = .hosted()
        }
    }

    /// Create throws → error toast. Composer is seeded; fire `.createTask` from the preview.
    public static func createFails() -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        state.composer = ComposerReducer.State(title: "Walk the dog", weight: 2)
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            let session = PreviewSummarySession(PreviewData.summary)
            $0.summaryClient.fetch = { session.summary }
            $0.tasksClient.create = { _ in throw URLError(.timedOut) }
            $0.toastClient = .hosted()
        }
    }

    /// Happy-path create → success toast. Composer seeded; fire `.createTask` from the preview.
    public static func createSucceeds() -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        state.composer = ComposerReducer.State(title: "Walk the dog", weight: 2)
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            let session = PreviewSummarySession(PreviewData.summary)
            $0.summaryClient.fetch = { session.summary }
            $0.tasksClient = session.tasksClient
            $0.toastClient = .hosted()
        }
    }

    public static func composer() -> StoreOf<ComposerReducer> {
        Store(initialState: ComposerReducer.State()) {
            ComposerReducer()
        }
    }

    /// Repeat picked, so the "Repeat until" row is on screen with its stepper.
    public static func composerBoundedRepeat() -> StoreOf<ComposerReducer> {
        Store(
            initialState: ComposerReducer.State(
                title: "Water the plants",
                recurrence: .weekly,
                dueOption: .tomorrow,
                endOption: .afterCount,
                endCount: 6
            )
        ) {
            ComposerReducer()
        }
    }

    public static func composerEditing() -> StoreOf<ComposerReducer> {
        Store(
            initialState: ComposerReducer.State(
                editing: PreviewData.laundry,
                meId: PreviewData.ada.id
            )
        ) {
            ComposerReducer()
        }
    }
}

/// In-memory summary for canvas — toggle/delete/create mutate it so refresh
/// after an action doesn’t clobber the UI with a static fixture.
private final class PreviewSummarySession: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Summary

    init(_ summary: Summary) {
        value = summary
    }

    var summary: Summary {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    var tasksClient: TasksClient {
        TasksClient(
            create: { [self] body in
                // Mirror the server: a count is echoed back alongside the end
                // date it derives (`docs/product/API.md` → Recurrence).
                let calendar = Calendar.evenHousehold
                let anchor = body.dueOn.flatMap(calendar.evenParseCivilDate) ?? Date()
                let until = body.recurrenceCount == nil
                    ? body.recurrenceUntil
                    : body.recurrence.recurrenceEnd(anchor: anchor, count: body.recurrenceCount)
                    .map(calendar.evenCivilDateString(from:))
                let task = HouseholdTask(
                    id: UUID(),
                    title: body.title,
                    section: body.section,
                    ownerMemberId: body.ownerMemberId,
                    weight: body.weight,
                    recurrence: body.recurrence,
                    dueOn: body.dueOn,
                    dueTime: body.dueTime,
                    recurrenceUntil: until,
                    recurrenceCount: body.recurrenceCount,
                    done: false,
                    metaLine: HouseholdTask.makeMetaLine(
                        dueOn: body.dueOn,
                        dueTime: body.dueTime,
                        recurrence: body.recurrence,
                        recurrenceUntil: until,
                        recurrenceCount: body.recurrenceCount
                    )
                )
                // Optimistic create already appended a local-id row; replace that
                // match so a later refresh doesn’t double the task.
                mutate { summary in
                    if let sectionIndex = summary.sections.firstIndex(where: { $0.key == body.section }),
                       let taskIndex = summary.sections[sectionIndex].tasks.lastIndex(where: {
                           $0.title == body.title
                               && $0.ownerMemberId == body.ownerMemberId
                               && !$0.done
                       })
                    {
                        summary.sections[sectionIndex].tasks[taskIndex] = task
                    } else {
                        summary.insertingCreatedTask(task)
                    }
                }
                return task
            },
            toggle: { [self] id in
                var toggled = PreviewData.laundry
                mutate { summary in
                    guard var task = summary.sections.flatMap(\.tasks).first(where: { $0.id == id })
                    else { return }
                    task.done.toggle()
                    task.doneByMemberId = task.done ? task.ownerMemberId : nil
                    summary.applyToggleResult(
                        task,
                        meId: PreviewData.ada.id,
                        meName: PreviewData.ada.displayName,
                        partnerId: PreviewData.umut.id,
                        partnerName: PreviewData.umut.displayName
                    )
                    toggled = task
                }
                return toggled
            },
            delete: { [self] id in
                mutate {
                    $0.removingTask(
                        id: id,
                        meId: PreviewData.ada.id,
                        meName: PreviewData.ada.displayName,
                        partnerId: PreviewData.umut.id,
                        partnerName: PreviewData.umut.displayName
                    )
                }
            },
            update: { [self] id, body in
                let calendar = Calendar.evenHousehold
                let clearEnd = body.clearRecurrenceEnd
                let until: String? = {
                    if clearEnd { return nil }
                    if body.recurrenceCount == nil { return body.recurrenceUntil }
                    let anchor = body.dueOn.flatMap(calendar.evenParseCivilDate) ?? Date()
                    return body.recurrence.recurrenceEnd(anchor: anchor, count: body.recurrenceCount)
                        .map(calendar.evenCivilDateString(from:))
                }()
                let count = clearEnd ? nil : body.recurrenceCount
                var updated = PreviewData.laundry
                mutate { summary in
                    guard var task = summary.sections.flatMap(\.tasks).first(where: { $0.id == id })
                    else { return }
                    task.title = body.title
                    task.section = body.section
                    task.ownerMemberId = body.ownerMemberId
                    task.weight = body.weight
                    task.recurrence = body.recurrence
                    task.dueOn = body.clearDueOn ? nil : body.dueOn
                    // The hour hangs off the date — clearing the day clears it.
                    task.dueTime = (body.clearDueTime || task.dueOn == nil) ? nil : body.dueTime
                    task.recurrenceUntil = until
                    task.recurrenceCount = count
                    task.metaLine = HouseholdTask.makeMetaLine(
                        originLabel: HouseholdTask.originLabel(fromMetaLine: task.metaLine),
                        dueOn: task.dueOn,
                        dueTime: task.dueTime,
                        recurrence: task.recurrence,
                        recurrenceUntil: task.recurrenceUntil,
                        recurrenceCount: task.recurrenceCount
                    )
                    summary.replacingTask(id: id, with: task)
                    updated = task
                }
                return updated
            }
        )
    }

    private func mutate(_ body: (inout Summary) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&value)
    }
}

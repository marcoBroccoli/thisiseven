import AuthClient
import ComposableArchitecture
import EvenCore
import Foundation
import SummaryClient
import TasksClient
import ToastClient
import ToastUI
import WidgetClient

/// How Today regroups the summary list. Client-only — `/v1/summary` still
/// returns chore/admin sections; the Feature remaps for display.
public enum TodayOrganizeMode: String, CaseIterable, Equatable, Sendable {
    case day
    case type
    case person

    public var pillLabel: String {
        switch self {
        case .day: "Day"
        case .type: "Type"
        case .person: "Person"
        }
    }
}

/// Who may change a todo. Both partners *see* the whole week — the beam only
/// reads honestly when both sides are visible — but completing, editing and
/// deleting belong to the member it is assigned to (`403 not_owner` server
/// side). Creating work for the other partner stays allowed, and a Trade is how
/// an existing todo moves across.
///
/// An unknown `me` (members still loading) is not "the partner's": the server
/// is the authority, this layer only keeps the affordances honest.
public enum TodayTaskPermission {
    public static func canWrite(_ task: HouseholdTask, me: Member?) -> Bool {
        guard let me else { return true }
        return task.ownerMemberId == me.id
    }
}

@Reducer
public struct TodayReducer {
    @ObservableState
    public struct State: Equatable {
        public var summary: Summary?
        public var me: Member?
        public var partner: Member?
        /// Starts true so the first frame paints a redacted skeleton, not empty.
        public var isLoading = true
        /// Default Day — Overdue · Today · Tomorrow · Later · No date.
        public var organizeMode: TodayOrganizeMode = .day
        @Presents public var composer: ComposerReducer.State?
        public init() {}

        /// The row-level gate the view reads and the reducer re-checks — a
        /// stale client must not fire a write the server will refuse.
        public func canWrite(_ task: HouseholdTask) -> Bool {
            TodayTaskPermission.canWrite(task, me: me)
        }
    }

    public enum Action: ViewAction {
        case view(View)
        case membersLoaded(Member?, Member?)
        case summaryLoaded(Summary)
        /// Create succeeded — swap optimistic local id for the API task + toast.
        case createSucceeded(localId: UUID, task: HouseholdTask)
        /// Update succeeded — merge server fields onto the optimistic row + toast.
        case updateSucceeded(task: HouseholdTask)
        case composer(PresentationAction<ComposerReducer.Action>)
        case createTask
        case updateTask
        case delegate(Delegate)
        /// Toast — `ToastClient` → feature `.evenToastHost()`.
        case presentToast(Toast)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case refresh
            case toggle(UUID)
            case edit(UUID)
            case delete(UUID)
            case addTapped
            case organize(TodayOrganizeMode)
        }

        public enum Delegate: Equatable {
            case openInbox
        }
    }

    @Dependency(\.summaryClient) var summaryClient
    @Dependency(\.tasksClient) var tasksClient
    @Dependency(\.widgetClient) var widgetClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.toastClient) var toastClient
    @Dependency(\.context) var context

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appear):
                // Don't flash skeleton when summary is already on screen (tab revisit).
                if state.summary == nil {
                    state.isLoading = true
                }
                return .merge(
                    loadSummary(),
                    .run { [authClient] send in
                        let members = await authClient.householdMembers()
                        await send(.membersLoaded(members.me, members.partner))
                    }
                )

            case let .membersLoaded(me, partner):
                state.me = me
                state.partner = partner
                return .none

            case let .summaryLoaded(summary):
                state.isLoading = false
                state.summary = summary
                return publishWidget(summary)

            case .view(.refresh):
                // Empty (no summary): show skeleton. With content, keep the list
                // and let `.refreshable` own the spinner.
                let empty = state.summary == nil
                if empty { state.isLoading = true }
                return loadSummary(surviveStoreTaskCancellation: empty)

            case let .view(.toggle(id)):
                // Snappy local path: flip check + pebble immediately, POST in
                // the background. Partner devices refetch via household WS.
                guard var summary = state.summary,
                      var task = summary.sections.flatMap(\.tasks).first(where: { $0.id == id }),
                      state.canWrite(task)
                else { return .none }
                task.done.toggle()
                task.doneByMemberId = task.done ? task.ownerMemberId : nil
                summary.applyToggleResult(
                    task,
                    meId: state.me?.id,
                    meName: state.me?.displayName ?? "You",
                    partnerId: state.partner?.id,
                    partnerName: state.partner?.displayName ?? "Partner"
                )
                state.summary = summary
                let widgetSummary = summary
                return .merge(
                    publishWidget(widgetSummary),
                    .run { [tasksClient] send in
                        do {
                            _ = try await tasksClient.toggle(id)
                        } catch {
                            await send(.presentToast(.todayFailure(error, .toggle)))
                            await send(.view(.refresh))
                        }
                    }
                )

            case let .view(.edit(id)):
                guard let task = state.summary?.sections.flatMap(\.tasks).first(where: { $0.id == id }),
                      state.canWrite(task)
                else { return .none }
                state.composer = ComposerReducer.State(editing: task, meId: state.me?.id)
                return .none

            case let .view(.delete(id)):
                guard let existing = state.summary?.sections.flatMap(\.tasks)
                    .first(where: { $0.id == id }), state.canWrite(existing)
                else { return .none }
                if var summary = state.summary {
                    summary.removingTask(
                        id: id,
                        meId: state.me?.id,
                        meName: state.me?.displayName ?? "You",
                        partnerId: state.partner?.id,
                        partnerName: state.partner?.displayName ?? "Partner"
                    )
                    state.summary = summary
                }
                return .run { [tasksClient] send in
                    do {
                        try await tasksClient.delete(id)
                    } catch {
                        await send(.presentToast(.todayFailure(error, .delete)))
                        await send(.view(.refresh))
                    }
                }

            case .view(.addTapped):
                state.composer = ComposerReducer.State()
                return .none

            case let .view(.organize(mode)):
                state.organizeMode = mode
                return .none

            case .composer(.presented(.view(.saveTapped))):
                if state.composer?.isEditing == true {
                    return .send(.updateTask)
                }
                return .send(.createTask)

            case .composer(.presented(.view(.cancelTapped))):
                state.composer = nil
                return .none

            case .composer:
                return .none

            case .createTask:
                guard let composer = state.composer else { return .none }
                let owner = composer.ownerIsMe
                    ? (state.me?.id ?? state.summary?.pebbles.first?.memberId)
                    : (state.partner?.id ?? state.summary?.pebbles.dropFirst().first?.memberId)
                guard var summary = state.summary, let owner else { return .none }
                let title = composer.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let dueOn = composer.resolvedDueOnISO()
                let end = composer.recurrenceEnd()
                let body = EvenAPIClient.TaskDraftBody(
                    title: title,
                    section: composer.section,
                    ownerMemberId: owner,
                    weight: composer.weight,
                    recurrence: composer.recurrence,
                    dueOn: dueOn,
                    recurrenceUntil: end.until,
                    recurrenceCount: end.count
                )
                // TODO: Calendar reminder — TaskDraftBody / POST /v1/tasks has no
                // reminder field (drafts only). Wire when the tasks API gains one.
                // Snappy local path: append immediately, POST in the background.
                // Partner devices refetch via household WS.
                let localId = UUID()
                // A count is the household's intent; mirror the server and derive
                // the end date from it so the row reads the same before and after
                // the POST lands.
                let localUntil = end.count == nil
                    ? end.until
                    : composer.recurrence.recurrenceEnd(
                        anchor: dueOn.flatMap(Calendar.evenHousehold.evenParseCivilDate) ?? Date(),
                        count: end.count
                    ).map(Calendar.evenHousehold.evenCivilDateString(from:))
                let localTask = HouseholdTask(
                    id: localId,
                    title: title,
                    section: composer.section,
                    ownerMemberId: owner,
                    weight: composer.weight,
                    recurrence: composer.recurrence,
                    dueOn: dueOn,
                    recurrenceUntil: localUntil,
                    recurrenceCount: end.count,
                    done: false,
                    metaLine: HouseholdTask.makeMetaLine(
                        dueOn: dueOn,
                        recurrence: composer.recurrence,
                        recurrenceUntil: localUntil,
                        recurrenceCount: end.count
                    )
                )
                summary.insertingCreatedTask(localTask)
                state.summary = summary
                state.composer = nil
                let widgetSummary = summary
                return .merge(
                    publishWidget(widgetSummary),
                    .run { [tasksClient] send in
                        do {
                            let created = try await tasksClient.create(body)
                            await send(.createSucceeded(localId: localId, task: created))
                        } catch {
                            await send(.presentToast(.todayFailure(error, .create)))
                            await send(.view(.refresh))
                        }
                    }
                )

            case .updateTask:
                guard let composer = state.composer,
                      let id = composer.editingTaskId,
                      var summary = state.summary,
                      let existing = summary.sections.flatMap(\.tasks).first(where: { $0.id == id }),
                      state.canWrite(existing)
                else { return .none }
                let owner = composer.ownerIsMe
                    ? (state.me?.id ?? existing.ownerMemberId)
                    : (state.partner?.id ?? existing.ownerMemberId)
                let title = composer.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let dueOn = composer.resolvedDueOnISO()
                let end = composer.recurrenceEnd()
                let clearDueOn = dueOn == nil
                // PATCH keeps the stored end when both fields are omitted — an
                // explicit clear is required to make a bounded repeat unbounded
                // again (`docs/product/API.md`).
                let clearRecurrenceEnd =
                    composer.recurrence == .none || composer.endOption == .never
                let body = EvenAPIClient.TaskDraftBody(
                    title: title,
                    section: composer.section,
                    ownerMemberId: owner,
                    weight: composer.weight,
                    recurrence: composer.recurrence,
                    dueOn: dueOn,
                    clearDueOn: clearDueOn,
                    recurrenceUntil: clearRecurrenceEnd ? nil : end.until,
                    recurrenceCount: clearRecurrenceEnd ? nil : end.count,
                    clearRecurrenceEnd: clearRecurrenceEnd
                )
                let localUntil = clearRecurrenceEnd
                    ? nil
                    : (end.count == nil
                        ? end.until
                        : composer.recurrence.recurrenceEnd(
                            anchor: dueOn.flatMap(Calendar.evenHousehold.evenParseCivilDate)
                                ?? Date(),
                            count: end.count
                        ).map(Calendar.evenHousehold.evenCivilDateString(from:)))
                let localCount = clearRecurrenceEnd ? nil : end.count
                var localTask = existing
                localTask.title = title
                localTask.section = composer.section
                localTask.ownerMemberId = owner
                localTask.weight = composer.weight
                localTask.recurrence = composer.recurrence
                localTask.dueOn = dueOn
                localTask.recurrenceUntil = localUntil
                localTask.recurrenceCount = localCount
                localTask.metaLine = HouseholdTask.makeMetaLine(
                    originLabel: HouseholdTask.originLabel(fromMetaLine: existing.metaLine),
                    dueOn: dueOn,
                    recurrence: composer.recurrence,
                    recurrenceUntil: localUntil,
                    recurrenceCount: localCount
                )
                if existing.done, existing.weight != localTask.weight {
                    if let idx = summary.pebbles.lastIndex(where: {
                        $0.memberId == existing.ownerMemberId && $0.weight == existing.weight
                    }) {
                        summary.pebbles[idx] = Pebble(
                            memberId: localTask.ownerMemberId,
                            weight: localTask.weight
                        )
                    }
                    summary.recomputeShares(
                        meId: state.me?.id,
                        meName: state.me?.displayName ?? "You",
                        partnerId: state.partner?.id,
                        partnerName: state.partner?.displayName ?? "Partner"
                    )
                } else if existing.done, existing.ownerMemberId != localTask.ownerMemberId {
                    if let idx = summary.pebbles.lastIndex(where: {
                        $0.memberId == existing.ownerMemberId && $0.weight == existing.weight
                    }) {
                        summary.pebbles[idx] = Pebble(
                            memberId: localTask.ownerMemberId,
                            weight: localTask.weight
                        )
                    }
                    summary.recomputeShares(
                        meId: state.me?.id,
                        meName: state.me?.displayName ?? "You",
                        partnerId: state.partner?.id,
                        partnerName: state.partner?.displayName ?? "Partner"
                    )
                }
                summary.replacingTask(id: id, with: localTask)
                state.summary = summary
                state.composer = nil
                let widgetSummary = summary
                return .merge(
                    publishWidget(widgetSummary),
                    .run { [tasksClient] send in
                        do {
                            let updated = try await tasksClient.update(id, body)
                            await send(.updateSucceeded(task: updated))
                        } catch {
                            await send(.presentToast(.todayFailure(error, .update)))
                            await send(.view(.refresh))
                        }
                    }
                )

            case let .createSucceeded(localId, task):
                if var summary = state.summary {
                    var merged = task
                    // Server/preview can omit the schedule fields while recurrence
                    // is set — keep the optimistic values so meta stays e.g.
                    // `TOMORROW · WEEKLY · 6 TIMES` instead of bare `WEEKLY`.
                    let local = summary.sections.flatMap(\.tasks).first { $0.id == localId }
                    merged.dueOn = merged.dueOn ?? local?.dueOn
                    merged.recurrenceUntil = merged.recurrenceUntil ?? local?.recurrenceUntil
                    merged.recurrenceCount = merged.recurrenceCount ?? local?.recurrenceCount
                    merged.metaLine = HouseholdTask.makeMetaLine(
                        originLabel: HouseholdTask.originLabel(fromMetaLine: task.metaLine),
                        dueOn: merged.dueOn,
                        recurrence: merged.recurrence,
                        recurrenceUntil: merged.recurrenceUntil,
                        recurrenceCount: merged.recurrenceCount
                    )
                    summary.replacingTask(id: localId, with: merged)
                    state.summary = summary
                }
                return toastEffect(Toast(message: "Added to Today", tone: .success))

            case let .updateSucceeded(task):
                if var summary = state.summary {
                    var merged = task
                    let local = summary.sections.flatMap(\.tasks).first { $0.id == task.id }
                    merged.dueOn = merged.dueOn ?? local?.dueOn
                    merged.recurrenceUntil = merged.recurrenceUntil ?? local?.recurrenceUntil
                    merged.recurrenceCount = merged.recurrenceCount ?? local?.recurrenceCount
                    // Preserve completion — PATCH doesn't touch done state.
                    merged.done = local?.done ?? merged.done
                    merged.doneByMemberId = local?.doneByMemberId ?? merged.doneByMemberId
                    merged.metaLine = HouseholdTask.makeMetaLine(
                        originLabel: HouseholdTask.originLabel(fromMetaLine: task.metaLine),
                        dueOn: merged.dueOn,
                        recurrence: merged.recurrence,
                        recurrenceUntil: merged.recurrenceUntil,
                        recurrenceCount: merged.recurrenceCount
                    )
                    summary.replacingTask(id: task.id, with: merged)
                    state.summary = summary
                }
                return toastEffect(Toast(message: "Saved", tone: .success))

            case let .presentToast(toast):
                if toast.tone == .error {
                    state.isLoading = false
                }
                return toastEffect(toast)

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$composer, action: \.composer) {
            ComposerReducer()
        }
    }

    private enum CancelID { case summary }

    /// - Parameter surviveStoreTaskCancellation: Empty pull-to-refresh swaps in a
    ///   skeleton; SwiftUI then cancels the refreshable task. That cancels the
    ///   `StoreTask` from `await send(.refresh).finish()`, and TCA `Send` drops
    ///   actions while cancelled — loading would stick. In live/preview we hop
    ///   the fetch off that task. Tests keep a structured await for TestStore.
    private func loadSummary(surviveStoreTaskCancellation: Bool = false) -> Effect<Action> {
        .run { [summaryClient, context, surviveStoreTaskCancellation] send in
            await Self.runFetch(
                surviveStoreTaskCancellation: surviveStoreTaskCancellation,
                context: context,
                send: send,
                fetch: { try await summaryClient.fetch() },
                success: { .summaryLoaded($0) },
                failure: { .presentToast(.todayFailure($0, .load)) }
            )
        }
        .cancellable(id: CancelID.summary, cancelInFlight: true)
    }

    private static func runFetch<Value: Sendable>(
        surviveStoreTaskCancellation: Bool,
        context: DependencyContext,
        send: Send<Action>,
        fetch: @escaping @Sendable () async throws -> Value,
        success: @escaping @Sendable (Value) -> Action,
        failure: @escaping @Sendable (Error) -> Action
    ) async {
        let fulfill: @MainActor @Sendable (Result<Value, Error>) -> Void = { result in
            switch result {
            case let .success(value):
                send(success(value))
            case let .failure(error) where error is CancellationError:
                break
            case let .failure(error):
                send(failure(error))
            }
        }

        if surviveStoreTaskCancellation, context != .test {
            Task { @MainActor in
                fulfill(await Result { try await fetch() })
            }
        } else {
            await fulfill(await Result { try await fetch() })
        }
    }

    private func toastEffect(_ toast: Toast) -> Effect<Action> {
        .run { [toastClient] _ in
            await toastClient.show(toast)
        }
    }

    private func publishWidget(_ summary: Summary) -> Effect<Action> {
        .run { [widgetClient] _ in
            let snap = EvenWidgetSnapshot(
                weekIndex: summary.week.index,
                clay: .init(
                    name: "A", initial: "A", color: .clay,
                    share: summary.percentMe, done: 0
                ),
                teal: .init(
                    name: "B", initial: "B", color: .teal,
                    share: summary.percentPartner, done: 0
                ),
                hasPartner: true,
                leader: summary.caption,
                leftToday: summary.sections.flatMap(\.tasks).filter { !$0.done }.count,
                upcoming: [],
                generatedAt: .now
            )
            await widgetClient.publish(snap)
        }
    }
}

public extension Summary {
    /// Apply a toggle the way `POST /v1/tasks/{id}/toggle` + `GET /v1/summary`
    /// would — used for the immediate local Today path (and preview session).
    mutating func applyToggleResult(
        _ task: HouseholdTask,
        meId: UUID?,
        meName: String,
        partnerId: UUID?,
        partnerName: String
    ) {
        for sectionIndex in sections.indices {
            guard let taskIndex = sections[sectionIndex].tasks.firstIndex(where: { $0.id == task.id })
            else { continue }
            let wasDone = sections[sectionIndex].tasks[taskIndex].done
            sections[sectionIndex].tasks[taskIndex] = task
            guard wasDone != task.done else { return }

            if task.done {
                pebbles.append(Pebble(memberId: task.ownerMemberId, weight: task.weight))
            } else {
                removingPebble(memberId: task.ownerMemberId, weight: task.weight)
            }
            recomputeShares(
                meId: meId,
                meName: meName,
                partnerId: partnerId,
                partnerName: partnerName
            )
            return
        }
    }

    /// Drop a task from the week. A completed one takes its pebble with it —
    /// a pan must never hold weight for work that no longer exists. Earlier
    /// occurrences of a repeat keep theirs; only `/v1/summary` knows about days
    /// this screen isn't showing.
    mutating func removingTask(
        id: UUID,
        meId: UUID? = nil,
        meName: String = "You",
        partnerId: UUID? = nil,
        partnerName: String = "Partner"
    ) {
        let removed = sections.flatMap(\.tasks).first { $0.id == id }
        sections = sections.map { section in
            var next = section
            next.tasks.removeAll { $0.id == id }
            return next
        }
        guard let removed, removed.done else { return }
        removingPebble(memberId: removed.ownerMemberId, weight: removed.weight)
        recomputeShares(
            meId: meId,
            meName: meName,
            partnerId: partnerId,
            partnerName: partnerName
        )
    }

    /// Take one pebble off a member's pan — the exact weight first, then any of
    /// theirs so a weight edited after completion can't strand it.
    private mutating func removingPebble(memberId: UUID, weight: Int) {
        if let idx = pebbles.lastIndex(where: {
            $0.memberId == memberId && $0.weight == weight
        }) {
            pebbles.remove(at: idx)
        } else if let idx = pebbles.lastIndex(where: { $0.memberId == memberId }) {
            pebbles.remove(at: idx)
        }
    }

    /// Append a freshly created task into its section (create a section if needed).
    mutating func insertingCreatedTask(_ task: HouseholdTask) {
        if let index = sections.firstIndex(where: { $0.key == task.section }) {
            sections[index].tasks.append(task)
        } else {
            sections.append(
                SummarySection(
                    key: task.section,
                    label: task.section == .chore ? "CHORES" : "ADMIN",
                    tasks: [task]
                )
            )
        }
    }

    /// Swap an optimistic local task for the API-returned one (id + meta).
    /// Relocates when the server section differs from the optimistic slot.
    mutating func replacingTask(id: UUID, with task: HouseholdTask) {
        for sectionIndex in sections.indices {
            guard let taskIndex = sections[sectionIndex].tasks.firstIndex(where: { $0.id == id })
            else { continue }
            if sections[sectionIndex].key == task.section {
                sections[sectionIndex].tasks[taskIndex] = task
            } else {
                sections[sectionIndex].tasks.remove(at: taskIndex)
                insertingCreatedTask(task)
            }
            return
        }
    }

    mutating func recomputeShares(
        meId: UUID?,
        meName: String,
        partnerId: UUID?,
        partnerName: String
    ) {
        let meWeight = pebbles.filter { $0.memberId == meId }.map(\.weight).reduce(0, +)
        let partnerWeight = pebbles.filter { $0.memberId == partnerId }.map(\.weight).reduce(0, +)
        let total = meWeight + partnerWeight
        if total == 0 {
            // No completions on either side yet — stay level. Matches the
            // backend's unconditional 50/50 default (see summary.go pctMe);
            // solo households used to tilt fully to "me" here with nothing
            // actually done.
            percentMe = 50
            percentPartner = 50
        } else {
            percentMe = Int((Double(meWeight) / Double(total) * 100).rounded())
            percentPartner = 100 - percentMe
        }
        caption = Self.beamCaption(
            total: total,
            percentMe: percentMe,
            meName: meName,
            partnerName: partnerName
        )
    }

    /// Mirrors `beamCaption` in `backend/internal/api/types.go`.
    static func beamCaption(
        total: Int,
        percentMe: Int,
        meName: String,
        partnerName: String
    ) -> String {
        guard total > 0 else { return "Empty pans. A new week, level by definition" }
        let diff = abs(percentMe - 50)
        switch diff {
        case ...1: return "Level. Enjoy it while it lasts"
        case ...4: return "Close to even. Not a competition — but noted"
        default:
            let leaning = percentMe < 50 ? partnerName : meName
            return "Leaning \(leaning) — mostly the admin and the remembering"
        }
    }
}

extension Toast {
    enum TodayFailure {
        case load, toggle, create, update, delete

        var fallback: String {
            switch self {
            case .load: "Couldn’t load today"
            case .toggle: "Couldn’t update task"
            case .create: "Couldn’t add task"
            case .update: "Couldn’t save changes"
            case .delete: "Couldn’t delete task"
            }
        }
    }

    static func todayFailure(_ error: Error, _ kind: TodayFailure) -> Toast {
        // A refused write is the one case where the server knows something the
        // app cannot infer from the row — say what it said, not "couldn't".
        // (Only reachable from a stale client: the row hides the affordance.)
        if let api = error as? APIError,
           case let .http(_, code, message) = api,
           code == "not_owner", !message.isEmpty
        {
            return .failure(message)
        }
        return .failure(from: error, offline: "Couldn’t reach Even", fallback: kind.fallback)
    }
}

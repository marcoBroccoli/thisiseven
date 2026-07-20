import Foundation
import Observation
import EvenCore

enum EvenTab: String, CaseIterable {
    case today, todos, schedule, money
}

/// The mobile app deliberately presents one household object: a todo. Gmail
/// suggestions need a quick review; saved work can be completed and, when it
/// has a date, lives in the shared Google Calendar.
struct TodoItem: Identifiable {
    enum State: Int {
        case needsReview = 0
        case open = 1
        case done = 2
    }

    enum Source: String {
        case gmail, calendar, manual

        var label: String {
            switch self {
            case .gmail: return "GMAIL"
            case .calendar: return "CALENDAR"
            case .manual: return "MANUAL"
            }
        }
    }

    let id: UUID
    let title: String
    let ownerMemberId: UUID
    let dueOn: String?
    let amountCents: Int?
    let state: State
    let source: Source
    let urgency: Int
    let task: HouseholdTask?
    let draft: Draft?

    init(task: HouseholdTask) {
        id = task.id
        title = task.title
        ownerMemberId = task.ownerMemberId
        dueOn = task.dueOn
        amountCents = nil
        state = task.done ? .done : .open
        source = task.googleEventUrl == nil ? .manual : .calendar
        urgency = 0
        self.task = task
        draft = nil
    }

    init(draft: Draft) {
        id = draft.id
        title = draft.title.isEmpty ? draft.subject : draft.title
        ownerMemberId = draft.ownerMemberId
        dueOn = draft.dueOn
        amountCents = draft.amountCents
        state = .needsReview
        source = draft.isFromGmail ? .gmail : .manual
        urgency = draft.urgency
        task = nil
        self.draft = draft
    }
}

/// Screen-facing store over the evend API. Everything here is real server
/// data — there is deliberately no seed/mock path (PRD hard rule).
@Observable
@MainActor
final class AppModel {
    let session: SessionStore

    var tab: EvenTab = .today
    var summary: Summary?
    var drafts: [Draft] = []
    var money: Money?
    var googleStatus: GoogleStatus?
    var gmailSyncing = false
    var calendarSyncing = false
    var calendarMonthItems: [CalendarItem] = []
    var calendarUpcoming: [CalendarItem] = []
    var calendarInfo: GoogleCalendarInfo?
    var calendarRevision = 0
    var resolvingCalendarTaskID: UUID?
    var todoReminderStatus: TodoReminderNotificationState = .needsPermission
    var todoReminderScheduling = false
    var reset: ResetSummary?
    var resetStep: Int = 0
    var lastClosedWeekIndex: Int?

    var stampMessage: String?
    var errorMessage: String?
    var isLoading = false

    private var stampTask: Task<Void, Never>?
    private let todoReminderNotifications = TodoReminderNotificationCoordinator()

    init(session: SessionStore) {
        self.session = session
    }

    var api: EvenAPIClient { session.api }
    var household: Household? { session.me?.household }
    var me: Member? { household?.me }
    var partner: Member? { household?.partner }

    var todos: [TodoItem] {
        let taskItems = (summary?.sections ?? [])
            .flatMap(\.tasks)
            .map(TodoItem.init(task:))
        let suggestedItems = drafts.map(TodoItem.init(draft:))
        return (suggestedItems + taskItems).sorted { lhs, rhs in
            if lhs.state.rawValue != rhs.state.rawValue {
                return lhs.state.rawValue < rhs.state.rawValue
            }
            if lhs.state == .needsReview, lhs.urgency != rhs.urgency {
                return lhs.urgency > rhs.urgency
            }
            let lhsDate = lhs.dueOn ?? "9999-12-31"
            let rhsDate = rhs.dueOn ?? "9999-12-31"
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var pendingReviewCount: Int { todos.filter { $0.state == .needsReview }.count }
    var scheduledTodoCount: Int { todos.filter { $0.source == .calendar }.count }
    var calendarIssueCount: Int {
        (summary?.sections ?? []).flatMap(\.tasks)
            .filter { $0.calendarSyncState?.requiresResolution == true }
            .count
    }

    func member(_ id: UUID?) -> Member? {
        household?.members.first(where: { $0.id == id })
    }

    // MARK: Loading

    func refreshAll() async {
        isLoading = summary == nil
        defer { isLoading = false }
        async let s = try? api.summary()
        async let d = try? api.pendingDrafts()
        async let g = try? api.googleStatus()
        let (summary, drafts, google) = await (s, d, g)
        if let summary { self.summary = summary }
        if let drafts { self.drafts = drafts }
        if let google { self.googleStatus = google }
        await refreshTodoReminders()
        if summary == nil && drafts == nil && google == nil {
            errorMessage = "Can't reach the house server."
        }
    }

    func refreshReset() async {
        reset = try? await api.resetSummary()
    }

    // MARK: Stamp

    func stamp(_ message: String) {
        stampTask?.cancel()
        stampMessage = message
        stampTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.stampMessage = nil
        }
    }

    private func surface(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    // MARK: Tasks

    func toggle(_ task: HouseholdTask) async {
        // Optimistic flip; server truth replaces it.
        setTask(task.with(done: !task.done))
        do {
            let updated = try await api.toggleTask(id: task.id)
            setTask(updated)
            self.summary = try await api.summary()
            await refreshTodoReminders()
        } catch {
            setTask(task)
            surface(error)
        }
    }

    private func setTask(_ task: HouseholdTask) {
        guard var summary else { return }
        summary.sections = summary.sections.map { section in
            var section = section
            section.tasks = section.tasks.map { $0.id == task.id ? task : $0 }
            return section
        }
        self.summary = summary
    }

    func createTask(_ body: EvenAPIClient.TaskDraftBody) async -> Bool {
        do {
            _ = try await api.createTask(body)
            summary = try await api.summary()
            calendarRevision += 1
            await refreshTodoReminders()
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func updateTask(id: UUID, _ body: EvenAPIClient.TaskDraftBody) async -> Bool {
        do {
            _ = try await api.updateTask(id: id, body)
            summary = try await api.summary()
            calendarRevision += 1
            await refreshTodoReminders()
            stamp(body.clearDueOn ? "REMOVED FROM CALENDAR" : "TODO UPDATED")
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func archive(_ task: HouseholdTask) async {
        do {
            try await api.deleteTask(id: task.id)
            summary = try await api.summary()
            calendarRevision += 1
            await refreshTodoReminders()
            stamp("TODO ARCHIVED")
        } catch {
            surface(error)
        }
    }

    func resolveCalendarIssue(_ task: HouseholdTask,
                              action: EvenAPIClient.CalendarResolutionAction) async -> Bool {
        guard resolvingCalendarTaskID == nil else { return false }
        resolvingCalendarTaskID = task.id
        defer { resolvingCalendarTaskID = nil }
        do {
            let updated = try await api.resolveTaskCalendar(id: task.id, action: action)
            setTask(updated)
            summary = try? await api.summary()
            calendarRevision += 1
            await refreshTodoReminders()

            if updated.calendarSyncState == .synced {
                switch action {
                case .acknowledge: stamp("CALENDAR CHANGE CONFIRMED")
                case .restore: stamp("RESTORED TO CALENDAR")
                case .retry: stamp("CALENDAR RETRIED")
                }
            } else {
                stamp("CALENDAR STILL NEEDS ATTENTION")
            }
            return true
        } catch {
            surface(error)
            return false
        }
    }

    // MARK: Drafts

    func propose(_ body: EvenAPIClient.ProposeDraftBody) async -> Bool {
        do {
            let draft = try await api.proposeDraft(body)
            drafts.insert(draft, at: 0)
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func updateDraft(id: UUID, _ patch: EvenAPIClient.DraftPatchBody) async -> Draft? {
        do {
            let updated = try await api.updateDraft(id: id, patch)
            if let i = drafts.firstIndex(where: { $0.id == id }) { drafts[i] = updated }
            return updated
        } catch {
            surface(error)
            return nil
        }
    }

    func approve(_ draft: Draft) async {
        do {
            _ = try await api.approveDraft(id: draft.id)
            drafts.removeAll { $0.id == draft.id }
            summary = try await api.summary()
            calendarRevision += 1
            await refreshTodoReminders()
            stamp("ON THE CALENDAR ✓")
        } catch {
            surface(error)
        }
    }

    func dismiss(_ draft: Draft) async {
        do {
            _ = try await api.dismissDraft(id: draft.id)
            drafts.removeAll { $0.id == draft.id }
            stamp("DISMISSED — IGNORED")
        } catch {
            surface(error)
        }
    }

    /// Kicks the backend scan job and polls it live: drafts stream into the
    /// inbox batch by batch while the loading state runs.
    func syncGmail() async {
        guard !gmailSyncing else { return }
        gmailSyncing = true
        defer { gmailSyncing = false }
        do {
            _ = try await api.googleSync()
        } catch {
            // A sync already in flight is fine — just join it and poll.
            if (error as? APIError)?.code != "sync_running" {
                surface(error)
                return
            }
        }
        var finalCreated = 0
        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let status = try? await api.googleStatus()
            if let fresh = try? await api.pendingDrafts() {
                drafts = fresh
            }
            if let status {
                googleStatus = status
                finalCreated = status.created ?? 0
                if !status.isSyncing { break }
            }
        }
        stamp(finalCreated > 0
              ? "GMAIL — \(finalCreated) NEW DRAFT\(finalCreated == 1 ? "" : "S")"
              : "GMAIL — NOTHING NEW")
    }

    // MARK: Calendar

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Loads the visible month (±7d) for the grid and the next-7-days agenda.
    func loadCalendar(month: Date) async {
        let cal = Foundation.Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let end = cal.date(byAdding: DateComponents(month: 1, day: 7), to: start) ?? month
        let from = Self.dayFormat.string(from: cal.date(byAdding: .day, value: -7, to: start) ?? start)
        let to = Self.dayFormat.string(from: end)
        async let monthReq = try? api.calendar(from: from, to: to)
        async let weekReq = try? api.calendar(
            from: Self.dayFormat.string(from: Date()),
            to: Self.dayFormat.string(from: cal.date(byAdding: .day, value: 7, to: Date()) ?? Date()))
        async let infoReq = try? api.calendarInfo()
        let (monthResp, weekResp, info) = await (monthReq, weekReq, infoReq)
        if let monthResp { calendarMonthItems = monthResp.items }
        if let weekResp { calendarUpcoming = weekResp.items }
        calendarInfo = info   // nil when not connected / not shared yet
    }

    /// Pull direct edits from the dedicated shared Calendar. This never reads
    /// a user's primary calendar and always refreshes local Todo state after
    /// a successful reconciliation pass.
    func syncCalendar() async {
        guard !calendarSyncing else { return }
        calendarSyncing = true
        defer { calendarSyncing = false }
        do {
            let result = try await api.syncCalendar()
            await refreshAll()
            calendarRevision += 1
            await loadCalendar(month: Date())
            let changed = result.imported + result.updated + result.deleted
            stamp(changed == 0 ? "CALENDAR — UP TO DATE" : "CALENDAR — \(changed) UPDATED")
        } catch {
            if (error as? APIError)?.code == "google_reconnect_required" {
                await refreshAll()
            }
            surface(error)
        }
    }

    // MARK: Phone reminders

    /// Refreshes local due-day alerts from the same Calendar occurrence feed
    /// shown in Schedule. No notification is sent until the user grants iOS
    /// permission, and no data is written outside the household API.
    func refreshTodoReminders() async {
        guard !todoReminderScheduling else { return }
        todoReminderScheduling = true
        defer { todoReminderScheduling = false }

        let permission = await todoReminderNotifications.status()
        guard permission.isAuthorized else {
            todoReminderStatus = permission
            return
        }
        guard let items = await upcomingReminderItems() else {
            todoReminderStatus = .unavailable("Couldn't load upcoming todos.")
            return
        }
        todoReminderStatus = await todoReminderNotifications.replaceScheduledReminders(items: items)
    }

    func enableTodoReminders() async {
        guard !todoReminderScheduling else { return }
        todoReminderScheduling = true
        defer { todoReminderScheduling = false }

        let permission = await todoReminderNotifications.requestAuthorization()
        guard permission.isAuthorized else {
            todoReminderStatus = permission
            return
        }
        guard let items = await upcomingReminderItems() else {
            todoReminderStatus = .unavailable("Couldn't load upcoming todos.")
            return
        }
        todoReminderStatus = await todoReminderNotifications.replaceScheduledReminders(items: items)
    }

    private func upcomingReminderItems() async -> [CalendarItem]? {
        let calendar = Foundation.Calendar.autoupdatingCurrent
        let from = Self.dayFormat.string(from: calendar.startOfDay(for: Date()))
        let end = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let to = Self.dayFormat.string(from: end)
        return try? await api.calendar(from: from, to: to).items
    }

    // MARK: Money

    func addExpense(_ body: EvenAPIClient.ExpenseBody) async -> Bool {
        do {
            money = try await api.addExpense(body)
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func settle() async {
        do {
            money = try await api.settle()
            stamp("SETTLED — EVEN ON MONEY")
        } catch {
            surface(error)
        }
    }

    // MARK: Reset

    func setAppreciation(body: String?, said: Bool) async {
        do {
            _ = try await api.setMyAppreciation(body: body, said: said)
            await refreshReset()
        } catch {
            surface(error)
        }
    }

    func proposeTrade(taskId: UUID) async {
        do {
            _ = try await api.proposeTrade(taskId: taskId)
            await refreshReset()
        } catch {
            surface(error)
        }
    }

    func acceptTrade(_ trade: Trade, accepted: Bool) async {
        do {
            _ = try await api.acceptTrade(id: trade.id, accepted: accepted)
            await refreshReset()
        } catch {
            surface(error)
        }
    }

    func closeWeek() async -> Bool {
        do {
            let closed = try await api.closeWeek()
            lastClosedWeekIndex = closed.closedWeek.index
            await refreshAll()
            await refreshReset()
            return true
        } catch {
            surface(error)
            return false
        }
    }
}

private extension HouseholdTask {
    func with(done: Bool) -> HouseholdTask {
        var copy = self
        copy.done = done
        return copy
    }
}

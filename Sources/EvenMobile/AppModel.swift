import Foundation
import Observation
import EvenCore

enum EvenTab: String, CaseIterable {
    case today, calendar, inbox, money, reset
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
    var calendarMonthItems: [CalendarItem] = []
    var calendarUpcoming: [CalendarItem] = []
    var calendarInfo: GoogleCalendarInfo?
    var reset: ResetSummary?
    var resetStep: Int = 0
    var lastClosedWeekIndex: Int?

    var stampMessage: String?
    var errorMessage: String?
    var isLoading = false

    private var stampTask: Task<Void, Never>?

    init(session: SessionStore) {
        self.session = session
    }

    var api: EvenAPIClient { session.api }
    var household: Household? { session.me?.household }
    var me: Member? { household?.me }
    var partner: Member? { household?.partner }

    func member(_ id: UUID?) -> Member? {
        household?.members.first(where: { $0.id == id })
    }

    // MARK: Loading

    func refreshAll() async {
        isLoading = summary == nil
        defer { isLoading = false }
        async let s = try? api.summary()
        async let d = try? api.pendingDrafts()
        async let m = try? api.money()
        async let g = try? api.googleStatus()
        let (summary, drafts, money, google) = await (s, d, m, g)
        if let summary { self.summary = summary }
        if let drafts { self.drafts = drafts }
        if let money { self.money = money }
        if let google { self.googleStatus = google }
        if summary == nil && drafts == nil && money == nil {
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

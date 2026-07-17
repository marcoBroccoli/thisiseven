import Foundation
import Observation
import EvenCore

enum EvenTab: String, CaseIterable {
    case today, inbox, money, reset
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

    func syncGmail() async {
        gmailSyncing = true
        defer { gmailSyncing = false }
        do {
            let result = try await api.googleSync()
            drafts = (try? await api.pendingDrafts()) ?? drafts
            googleStatus = try? await api.googleStatus()
            stamp(result.created > 0
                  ? "GMAIL — \(result.created) NEW DRAFT\(result.created == 1 ? "" : "S")"
                  : "GMAIL — NOTHING NEW")
        } catch {
            surface(error)
        }
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

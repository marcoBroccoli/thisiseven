import Foundation
import HouseholdCore

@MainActor
final class DemoHouseholdStore: ObservableObject {
    @Published private(set) var model: InboxPresentationModel
    @Published var selectedSection: HouseholdSection = .today
    @Published var syncMessage = "Ready. Gmail import discovers likely household emails."
    @Published var titleDraft = ""
    @Published var amountDraft = ""
    @Published var dueDateDraft = Date()
    @Published var newItemTitle = ""
    @Published var newItemAmount = ""
    @Published var newItemDueDate = Date().addingTimeInterval(86_400)
    @Published var newItemHasDueDate = true
    @Published var newItemRecurrence: HouseholdRecurrence?
    @Published var newItemOwnerID = ""
    @Published var newItemAreaID = ""
    @Published var replyDraft = ""
    @Published var googleClientID = ""
    @Published var googleClientSecret = ""
    @Published var googleCalendarID = "primary"
    @Published var googleExpectedAccount = "house.marcansu@gmail.com"
    @Published private(set) var googleConnectionStatus = "Not connected"
    @Published private(set) var lastGoogleError = ""
    @Published private(set) var isGoogleConnected = false
    @Published private(set) var isConnectingGoogle = false
    @Published private(set) var isSavingGmailDraft = false
    @Published private(set) var localReminderStatus = "Checking notification permission..."
    @Published private(set) var isSchedulingLocalReminders = false
    @Published private var activeWorkNow = Date()

    let household: HouseholdContext
    let gmailLabel = "HouseholdTodo"

    private let demoGmail: GmailClient
    private let extractor: EmailExtractor
    private let intelligenceAnalyzer = EmailIntelligenceAnalyzer()
    private let localStore: HouseholdLocalStore
    private let googleTokenStore = GoogleKeychainTokenStore()
    private let localReminderNotifications = LocalReminderNotificationCoordinator()
    private let appBaseURL = URL(string: "household://drafts")!
    private var localState: LocalHouseholdState
    private var localReminderRefreshTask: Task<Void, Never>?
    private var activeWorkRefreshTask: Task<Void, Never>?
    private static let googleClientIDDefaultsKey = "HouseholdCommandCenter.GoogleClientID"
    private static let googleCalendarIDDefaultsKey = "HouseholdCommandCenter.GoogleCalendarID"
    private static let requiredGoogleScopes = Set([
        GoogleOAuthScope.gmailReadonly.rawValue,
        GoogleOAuthScope.gmailCompose.rawValue,
        GoogleOAuthScope.calendarEvents.rawValue
    ])

    init() {
        let seed = DemoSeedData.make()
        let localStore = HouseholdLocalStore(fileURL: Self.defaultLocalStoreURL())
        let loadedState = (try? localStore.load()) ?? LocalHouseholdState()
        var seededState = loadedState
        seededState.drafts = seed.initialDrafts
        let initialState = loadedState.drafts.isEmpty ? seededState : loadedState
        self.household = seed.household
        self.demoGmail = DemoGmailClient(messages: seed.emails)
        self.extractor = DemoEmailExtractor(resultsByMessageID: seed.extractions)
        self.localStore = localStore
        self.localState = initialState
        self.model = InboxPresentationModel(drafts: initialState.drafts)
        self.googleClientID = UserDefaults.standard.string(forKey: Self.googleClientIDDefaultsKey)
            ?? Self.bundledGoogleClientID
            ?? ""
        self.googleCalendarID = UserDefaults.standard.string(forKey: Self.googleCalendarIDDefaultsKey) ?? "primary"
        refreshEditorFields()
        refreshGoogleConnectionStatus()
        Task { await refreshLocalReminderNotifications() }
        startActiveWorkClock()
    }

    deinit {
        localReminderRefreshTask?.cancel()
        activeWorkRefreshTask?.cancel()
    }

    var selectedDraft: InboxDraft? {
        model.selectedDraft
    }

    var dashboard: HouseholdDashboard {
        HouseholdDashboard(household: household, drafts: model.drafts, now: activeWorkNow)
    }

    var triageBuckets: [InboxTriageBucket] {
        model.triageBuckets(household: household, now: activeWorkNow)
    }

    var todaySections: [TodayReviewSection] {
        TodayReviewModel(drafts: model.drafts, household: household, now: activeWorkNow).sections
    }

    var urgentCount: Int {
        visibleDrafts.filter { intelligence(for: $0).urgency == .immediate }.count
    }

    var replyNeededCount: Int {
        visibleDrafts.filter { draft in
            if let replyStatus = draft.replyStatus, replyStatus != .none {
                return replyStatus.requiresReplyAction
            }

            return intelligence(for: draft).tags.contains(.replyNeeded)
        }.count
    }

    var bankingCandidateDrafts: [InboxDraft] {
        visibleDrafts.filter { intelligence(for: $0).tags.contains(.bankingCandidate) }
    }

    var snoozedDrafts: [InboxDraft] {
        model.drafts
            .filter {
                DraftSnoozeService.isCurrentlySnoozed($0, now: activeWorkNow)
                    && !($0.triageState?.isClosed ?? false)
                    && $0.status != .approved
                    && $0.status != .rejected
            }
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }
    }

    var bankTransactions: [BankTransaction] {
        localState.bankTransactions.sorted { left, right in
            left.bookingDate > right.bookingDate
        }
    }

    var bankingMatchSuggestions: [BankMatchSuggestion] {
        BankingReconciliation.suggestions(
            drafts: bankingCandidateDrafts,
            transactions: localState.bankTransactions,
            storedMatches: localState.bankMatches
        )
    }

    var confirmedBankMatchCount: Int {
        localState.bankMatches.filter { $0.status == .confirmed }.count
    }

    var unmatchedOutgoingTransactionCount: Int {
        let confirmedTransactionIDs = Set(
            localState.bankMatches
                .filter { $0.status == .confirmed }
                .map(\.transactionID)
        )
        return localState.bankTransactions.filter {
            $0.isOutgoing && !confirmedTransactionIDs.contains($0.id)
        }.count
    }

    var lastBankImportText: String {
        guard let lastBankImportAt = localState.lastBankImportAt else {
            return "No statement imported"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastBankImportAt)
    }

    var nextActionDraft: InboxDraft? {
        if let todayDraft = todaySections.flatMap(\.drafts).first {
            return todayDraft
        }

        return triageBuckets.flatMap(\.drafts).first
    }

    var calendarActionCount: Int {
        calendarReminderGroups
            .filter { $0.state != .scheduled }
            .reduce(0) { $0 + $1.drafts.count }
    }

    var scheduledCalendarCount: Int {
        calendarReminderGroups
            .first(where: { $0.state == .scheduled })?
            .drafts
            .count ?? 0
    }

    var reminderDrafts: [InboxDraft] {
        visibleDrafts
            .filter { $0.dueDate != nil && $0.status != .rejected }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case (.some(let lhsDue), .some(let rhsDue)):
                    return lhsDue < rhsDue
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title < rhs.title
                }
            }
    }

    var localStoragePath: String {
        localStore.fileURL.path
    }

    var ignoredSenderCount: Int {
        localState.ignoredSenders.count
    }

    var lastCalendarSyncText: String {
        guard let lastCalendarSyncAt = localState.lastCalendarSyncAt else {
            return "Never"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastCalendarSyncAt)
    }

    var calendarReminderGroups: [CalendarReminderGroup] {
        let groups = Dictionary(grouping: visibleDrafts.filter { $0.status != .rejected }) { draft in
            calendarReadiness(for: draft).state
        }

        return CalendarReadinessState.reminderOrder.compactMap { state in
            guard let drafts = groups[state], !drafts.isEmpty else { return nil }
            return CalendarReminderGroup(
                state: state,
                drafts: drafts.sortedByCalendarReadiness()
            )
        }
    }

    func selectDraft(id: UUID) {
        model.selectDraft(id: id)
        refreshEditorFields()
    }

    func intelligence(for draft: InboxDraft) -> EmailIntelligenceResult {
        intelligenceAnalyzer.analyze(draft: draft, household: household, now: Date())
    }

    func calendarReadiness(for draft: InboxDraft) -> CalendarReadiness {
        CalendarReadinessEvaluator.evaluate(draft: draft, intelligence: intelligence(for: draft))
    }

    func importGmailLabel() async {
        guard !shouldBlockGoogleDemoFallback else {
            syncMessage = "Google needs reconnecting before live Gmail import. Open Settings and select Reconnect Google."
            return
        }

        let importMode = isGoogleConnected ? "live Gmail" : "demo Gmail"
        syncMessage = "Importing and organizing household emails from \(importMode)..."
        let service = HouseholdInboxImportService(gmail: gmailClientForImport(), extractor: extractor, label: gmailLabel)

        do {
            let drafts = try await service.importDraftsThrowing(in: household)
            let selectedID = model.selectedDraftID
            let previousIDs = Set(model.drafts.map(\.id))
            localState.drafts = model.drafts
            localState = localState.mergingImportedDrafts(drafts)
            model = InboxPresentationModel(drafts: localState.drafts)
            if let selectedID {
                model.selectDraft(id: selectedID)
            }
            refreshEditorFields()
            persistCurrentState()
            let newCount = localState.drafts.filter { !previousIDs.contains($0.id) }.count
            syncMessage = "Imported \(drafts.count) emails from \(importMode). Added \(newCount) new draft(s); existing edits were preserved."
        } catch {
            recordGoogleReconnectIfNeeded(error.localizedDescription)
            syncMessage = "Import failed from \(importMode): \(error.localizedDescription)"
        }
    }

    func enableLocalReminderNotifications() async {
        isSchedulingLocalReminders = true
        let state = await localReminderNotifications.requestPermissionAndSchedule(
            drafts: model.drafts,
            household: household
        )
        localReminderStatus = state.statusText
        isSchedulingLocalReminders = false
    }

    func refreshLocalReminderNotifications() async {
        isSchedulingLocalReminders = true
        let state = await localReminderNotifications.scheduleIfAuthorized(
            drafts: model.drafts,
            household: household
        )
        localReminderStatus = state.statusText
        isSchedulingLocalReminders = false
    }

    func connectGoogle() async {
        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = effectiveGoogleClientSecret()
        let calendarID = normalizedGoogleCalendarID()
        guard !clientID.isEmpty else {
            googleConnectionStatus = googleClientIDRequirement
            syncMessage = googleConnectionStatus
            return
        }

        googleClientID = clientID
        googleCalendarID = calendarID
        UserDefaults.standard.set(clientID, forKey: Self.googleClientIDDefaultsKey)
        UserDefaults.standard.set(calendarID, forKey: Self.googleCalendarIDDefaultsKey)
        isConnectingGoogle = true
        lastGoogleError = ""
        googleConnectionStatus = "Opening Google sign-in for \(googleExpectedAccount)..."
        syncMessage = googleConnectionStatus

        defer { isConnectingGoogle = false }

        do {
            #if os(iOS)
            let coordinator = GoogleMobileOAuthCoordinator()
            let identity = try await coordinator.connect(
                clientID: clientID,
                accountHint: googleExpectedAccount
            )
            guard Self.requiredGoogleScopes.isSubset(of: Set(identity.grantedScopes)) else {
                throw GoogleMobileOAuthError.missingAccessToken
            }
            isGoogleConnected = true
            lastGoogleError = ""
            googleConnectionStatus = "Connected for \(identity.accountHint). Gmail and Calendar are live."
            syncMessage = "Google connected. Gmail import and Calendar approval are live."
            #else
            let coordinator = GoogleDesktopOAuthCoordinator(tokenStore: googleTokenStore)
            let tokens = try await coordinator.connect(
                clientID: clientID,
                clientSecret: clientSecret,
                accountHint: googleExpectedAccount
            )
            isGoogleConnected = true
            lastGoogleError = ""
            googleConnectionStatus = "Connected for \(tokens.accountHint). Gmail and Calendar are live."
            syncMessage = "Google connected. Gmail import and Calendar approval are live."
            #endif
        } catch {
            isGoogleConnected = false
            lastGoogleError = error.localizedDescription
            googleConnectionStatus = "Google connection failed: \(error.localizedDescription)"
            syncMessage = googleConnectionStatus
        }
    }

    func disconnectGoogle() {
        #if os(iOS)
        GoogleMobileOAuthCoordinator.signOut()
        isGoogleConnected = false
        lastGoogleError = ""
        googleConnectionStatus = "Disconnected. Import uses demo Gmail data."
        syncMessage = googleConnectionStatus
        #else
        do {
            try googleTokenStore.clear()
            isGoogleConnected = false
            lastGoogleError = ""
            googleConnectionStatus = "Disconnected. Import uses demo Gmail data."
            syncMessage = googleConnectionStatus
        } catch {
            googleConnectionStatus = "Disconnect failed: \(error.localizedDescription)"
            syncMessage = googleConnectionStatus
        }
        #endif
    }

    func refreshGoogleConnectionStatus() {
        #if os(iOS)
        isGoogleConnected = GoogleMobileOAuthCoordinator.hasCurrentUser
        if isGoogleConnected {
            lastGoogleError = ""
            googleConnectionStatus = "Google session restored. Gmail and Calendar are live."
        } else if lastGoogleError.isEmpty {
            googleConnectionStatus = "Not connected. Import uses demo Gmail data."
        }
        #else
        do {
            if let tokens = try googleTokenStore.load() {
                if googleClientID.isEmpty {
                    googleClientID = tokens.clientID
                }
                if googleClientSecret.isEmpty {
                    googleClientSecret = tokens.clientSecret ?? ""
                }

                guard Self.requiredGoogleScopes.isSubset(of: Set(tokens.grantedScopes)) else {
                    isGoogleConnected = false
                    lastGoogleError = "The saved Google authorization predates the current Gmail and Calendar permissions."
                    googleConnectionStatus = "Reconnect Google to grant Gmail read, Gmail Draft, and Calendar access."
                    return
                }

                isGoogleConnected = true
                lastGoogleError = ""
                googleConnectionStatus = "Connected for \(tokens.accountHint)."
            } else {
                isGoogleConnected = false
                if lastGoogleError.isEmpty {
                    googleConnectionStatus = "Not connected. Import uses demo Gmail data."
                }
            }
        } catch {
            isGoogleConnected = false
            lastGoogleError = error.localizedDescription
            googleConnectionStatus = "Keychain read failed: \(error.localizedDescription)"
        }
        #endif
    }

    func restoreGoogleSession() async {
        #if os(iOS)
        guard !googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            refreshGoogleConnectionStatus()
            return
        }

        do {
            let coordinator = GoogleMobileOAuthCoordinator()
            guard let identity = try await coordinator.restorePreviousSignIn() else {
                refreshGoogleConnectionStatus()
                return
            }

            guard Self.requiredGoogleScopes.isSubset(of: Set(identity.grantedScopes)) else {
                isGoogleConnected = false
                lastGoogleError = "The saved Google authorization is missing Gmail or Calendar permissions."
                googleConnectionStatus = "Reconnect Google to grant Gmail and Calendar access."
                return
            }

            isGoogleConnected = true
            lastGoogleError = ""
            googleConnectionStatus = "Connected for \(identity.accountHint). Gmail and Calendar are live."
        } catch {
            isGoogleConnected = false
            lastGoogleError = error.localizedDescription
            googleConnectionStatus = "Google session restore failed: \(error.localizedDescription)"
        }
        #else
        refreshGoogleConnectionStatus()
        #endif
    }

    func approveSelectedDraft() async {
        guard let selectedDraft else { return }
        guard !shouldBlockGoogleDemoFallback else {
            syncMessage = "Google needs reconnecting before Calendar changes can be made. Open Settings and select Reconnect Google."
            return
        }
        if selectedDraft.status == .calendarUpdateRequired, selectedDraft.googleEventID != nil {
            await syncSelectedCalendarUpdate()
            return
        }

        var draftForApproval = selectedDraft
        draftForApproval.snoozedUntil = nil
        let approvalMode = isGoogleConnected ? "Google Calendar \(normalizedGoogleCalendarID())" : "demo Calendar"
        syncMessage = "Creating event in \(approvalMode)..."
        let service = approvalServiceForCurrentConnection()
        let readiness = calendarReadiness(for: draftForApproval)
        let approved = await service.approve(
            draftForApproval,
            in: householdForApproval(),
            reminderMinutesBefore: readiness.recommendedReminderMinutesBefore
        )
        model.replaceDraft(approved)
        refreshEditorFields()
        persistCurrentState()

        switch approved.status {
        case .approved:
            syncMessage = "Approved and linked to Google Calendar event \(approved.googleEventID ?? "unknown")."
        case .calendarRetryRequired:
            recordGoogleReconnectIfNeeded(approved.lastError)
            syncMessage = "Calendar write needs retry: \(approved.lastError ?? "Unknown error")."
        default:
            syncMessage = "Draft moved to \(approved.status.rawValue)."
        }
    }

    func rejectSelectedDraft() {
        guard let selectedDraft else { return }
        var draftForRejection = selectedDraft
        draftForRejection.snoozedUntil = nil
        let rejected = approvalServiceForCurrentConnection().reject(draftForRejection, reason: "Rejected from Mac approval queue.")
        model.replaceDraft(rejected)
        refreshEditorFields()
        persistCurrentState()
        syncMessage = "Rejected draft. No Google Calendar event was created."
    }

    func markSelectedNotHousehold() {
        guard let selectedDraft else { return }
        updateSelected { draft in
            draft.triageState = .notHousehold
            draft.lastError = "Marked as not household."
            draft.snoozedUntil = nil
        }
        syncMessage = "Archived '\(selectedDraft.title)' as not household. It will stay out of the working inbox."
    }

    func markSelectedWaiting() {
        guard let selectedDraft else { return }
        updateSelected { draft in
            draft.triageState = .waiting
            draft.lastError = nil
        }
        syncMessage = "Moved '\(selectedDraft.title)' to Waiting."
    }

    func markSelectedDone() {
        guard let selectedDraft else { return }
        updateSelected { draft in
            draft.triageState = .done
            draft.replyStatus = .done
            draft.lastError = nil
            draft.snoozedUntil = nil
        }
        if selectedDraft.googleEventID != nil {
            syncMessage = "Marked '\(selectedDraft.title)' done locally. Its Calendar event remains as a record."
        } else {
            syncMessage = "Marked '\(selectedDraft.title)' done locally."
        }
    }

    func snoozeSelected(until date: Date) {
        guard let selectedDraft, selectedDraft.status == .pendingApproval else {
            syncMessage = "Only work that has not been approved to Calendar can be deferred here."
            return
        }
        guard date > Date() else {
            syncMessage = "Choose a future time to defer this work."
            return
        }

        updateSelected { draft in
            draft.snoozedUntil = date
        }
        syncMessage = "Deferred '\(selectedDraft.title)' until \(date.formatted(date: .abbreviated, time: .shortened)). Its due date is unchanged."
    }

    func snoozeSelectedLaterToday() {
        let now = Date()
        let calendar = Calendar.current
        let thisEvening = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: now)
        let date = (thisEvening ?? now) > now
            ? (thisEvening ?? now.addingTimeInterval(3 * 60 * 60))
            : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                .flatMap { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }
                ?? now.addingTimeInterval(86_400)
        snoozeSelected(until: date)
    }

    func snoozeSelectedTomorrowMorning() {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        snoozeSelected(until: date)
    }

    func snoozeSelectedNextWeek() {
        let now = Date()
        let date = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 9, minute: 0, weekday: 2),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(7 * 86_400)
        snoozeSelected(until: date)
    }

    func resumeSelectedNow() {
        guard let selectedDraft, selectedDraft.snoozedUntil != nil else { return }
        updateSelected { draft in
            draft.snoozedUntil = nil
        }
        syncMessage = "Returned '\(selectedDraft.title)' to the active inbox."
    }

    func markSelectedNeedsReply() {
        guard let selectedDraft else { return }
        updateSelected { draft in
            draft.replyStatus = .needsReply
            if draft.triageState == nil || draft.triageState == .done || draft.triageState == .notHousehold {
                draft.triageState = .active
            }
        }
        syncMessage = "Marked '\(selectedDraft.title)' as needing a reply."
    }

    func markSelectedReplyDone() {
        guard let selectedDraft else { return }
        updateSelected { draft in
            draft.replyStatus = .done
        }
        syncMessage = "Marked reply done for '\(selectedDraft.title)'."
    }

    func markSelectedReplySentManually() {
        guard let selectedDraft else { return }
        updateSelected { draft in
            draft.replyStatus = .sentManually
        }
        syncMessage = "Marked reply sent for '\(selectedDraft.title)'."
    }

    func ignoreSelectedSender() {
        guard let selectedDraft else { return }
        localState.ignoreSender(selectedDraft.source.from)
        updateSelected { draft in
            draft.triageState = .notHousehold
            draft.lastError = "Sender ignored locally: \(selectedDraft.source.from)"
            draft.snoozedUntil = nil
        }
        syncMessage = "Ignored \(selectedDraft.source.from). Future imports from this sender will be skipped."
    }

    func retrySelectedCalendarWrite() async {
        guard let selectedDraft else { return }
        if selectedDraft.status == .calendarUpdateRequired {
            await syncSelectedCalendarUpdate()
            return
        }

        guard selectedDraft.status == .calendarRetryRequired else {
            syncMessage = "This item does not need a Calendar retry."
            return
        }

        await approveSelectedDraft()
    }

    func syncSelectedCalendarUpdate() async {
        guard let selectedDraft else { return }
        guard !shouldBlockGoogleDemoFallback else {
            syncMessage = "Google needs reconnecting before Calendar changes can be made. Open Settings and select Reconnect Google."
            return
        }
        let approvalMode = isGoogleConnected ? "Google Calendar \(normalizedGoogleCalendarID())" : "demo Calendar"
        syncMessage = "Syncing existing event in \(approvalMode)..."
        let service = approvalServiceForCurrentConnection()
        let readiness = calendarReadiness(for: selectedDraft)
        let synced = await service.syncExistingCalendarEvent(
            selectedDraft,
            in: householdForApproval(),
            reminderMinutesBefore: readiness.recommendedReminderMinutesBefore
        )
        model.replaceDraft(synced)
        refreshEditorFields()
        persistCurrentState()

        switch synced.status {
        case .approved:
            syncMessage = "Synced updates to existing Google Calendar event \(synced.googleEventID ?? "unknown")."
        case .calendarRetryRequired:
            recordGoogleReconnectIfNeeded(synced.lastError)
            syncMessage = "Calendar update needs retry: \(synced.lastError ?? "Unknown error")."
        default:
            syncMessage = "Calendar sync moved draft to \(synced.status.rawValue)."
        }
    }

    func keepSelectedAppVersionForExternalChange() {
        guard let selectedDraft else { return }
        guard selectedDraft.status == .changedExternally else { return }
        model.replaceDraft(CalendarConflictResolver.keepAppVersion(for: selectedDraft))
        refreshEditorFields()
        persistCurrentState()
        syncMessage = "Kept the app record for '\(selectedDraft.title)'. Sync it to push this version back to Calendar."
    }

    func acceptSelectedCalendarVersion() {
        guard let selectedDraft else { return }
        guard selectedDraft.status == .changedExternally else { return }
        model.replaceDraft(CalendarConflictResolver.acceptCalendarVersion(for: selectedDraft))
        refreshEditorFields()
        persistCurrentState()
        syncMessage = "Accepted the Google Calendar version for '\(selectedDraft.title)'."
    }

    func recreateSelectedCalendarEvent() async {
        guard var selectedDraft else { return }
        selectedDraft.status = .pendingApproval
        selectedDraft.googleEventID = nil
        selectedDraft.googleEventURL = nil
        selectedDraft.calendarExternalSnapshot = nil
        selectedDraft.lastError = nil
        model.replaceDraft(selectedDraft)
        await approveSelectedDraft()
    }

    func markSelectedExternalChangeDone() {
        guard let selectedDraft else { return }
        guard selectedDraft.status == .changedExternally else { return }
        updateSelected { draft in
            draft.triageState = .done
            draft.lastError = nil
            draft.snoozedUntil = nil
        }
        syncMessage = "Resolved external Calendar change by marking '\(selectedDraft.title)' done."
    }

    func checkCalendarSync() async {
        let draftsWithEvents = model.drafts.filter { $0.googleEventID != nil }
        guard !draftsWithEvents.isEmpty else {
            syncMessage = "No approved Google Calendar events to sync yet."
            return
        }

        syncMessage = "Checking Google Calendar for external changes..."
        let service = approvalServiceForCurrentConnection()
        var changedCount = 0

        for draft in draftsWithEvents {
            var reconciled = await service.reconcileCalendarState(for: draft)
            if reconciled.status == .changedExternally {
                reconciled.snoozedUntil = nil
            }
            if reconciled != draft {
                changedCount += 1
            }
            model.replaceDraft(reconciled)
        }

        refreshEditorFields()
        localState.lastCalendarSyncAt = Date()
        persistCurrentState()
        syncMessage = changedCount == 0
            ? "Calendar sync checked \(draftsWithEvents.count) event(s). No external changes found."
            : "Calendar sync found \(changedCount) external change(s). Review them now."
    }

    func createManualItem() {
        let trimmedTitle = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            syncMessage = "Add a title before creating a manual household item."
            return
        }

        let amount = Decimal(string: newItemAmount.replacingOccurrences(of: ",", with: "."))
        let hasDueDate = newItemHasDueDate
        let recurrence = newItemRecurrence
        guard recurrence == nil || hasDueDate else {
            syncMessage = "Recurring work needs a first due date."
            return
        }
        let draft = ManualDraftFactory.makeDraft(
            title: trimmedTitle,
            dueDate: hasDueDate ? newItemDueDate : nil,
            amount: amount,
            ownerID: UUID(uuidString: newItemOwnerID),
            areaID: UUID(uuidString: newItemAreaID),
            recurrence: recurrence
        )

        model.replaceDraft(draft)
        model.selectDraft(id: draft.id)
        selectedSection = .inbox
        refreshEditorFields()
        resetManualItemFields()
        persistCurrentState()
        syncMessage = hasDueDate
            ? recurrence == nil
                ? "Created '\(trimmedTitle)'. Review it, then approve it to Google Calendar."
                : "Created recurring '\(trimmedTitle)'. Approve it to create the repeating Google Calendar event."
            : "Created '\(trimmedTitle)' without a due date. Add one when it becomes schedulable."
    }

    func beginManualItem() {
        resetManualItemFields()
        newItemHasDueDate = true
        newItemDueDate = Date().addingTimeInterval(86_400)
        newItemRecurrence = nil
        newItemOwnerID = household.members.first?.id.uuidString ?? ""
        newItemAreaID = household.areas.first?.id.uuidString ?? ""
    }

    func updateSelectedTitle(_ title: String) {
        titleDraft = title
        updateSelected { draft in
            draft.title = title
            markCalendarUpdateRequiredIfNeeded(&draft)
        }
    }

    func updateSelectedAmount(_ amount: String) {
        amountDraft = amount
        let normalized = amount.replacingOccurrences(of: ",", with: ".")
        updateSelected { draft in
            draft.amount = Decimal(string: normalized)
            markCalendarUpdateRequiredIfNeeded(&draft)
        }
    }

    func updateSelectedOwner(_ ownerID: UUID?) {
        updateSelected { draft in
            draft.ownerID = ownerID
            markCalendarUpdateRequiredIfNeeded(&draft)
        }
    }

    func updateSelectedArea(_ areaID: UUID?) {
        updateSelected { draft in
            draft.areaID = areaID
            markCalendarUpdateRequiredIfNeeded(&draft)
        }
    }

    func updateSelectedDueDate(_ dueDate: Date) {
        dueDateDraft = dueDate
        updateSelected { draft in
            draft.dueDate = dueDate
            markCalendarUpdateRequiredIfNeeded(&draft)
        }
    }

    func updateReplyDraft(_ reply: String) {
        replyDraft = reply
        guard let selectedDraft else { return }
        localState.setReplyText(reply, for: selectedDraft.id)
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReply.isEmpty, selectedDraft.replyStatus != .sentManually, selectedDraft.replyStatus != .done {
            var draft = selectedDraft
            draft.replyStatus = .drafted
            model.replaceDraft(draft)
        }
        persistCurrentState(saveCurrentReply: false)
    }

    func copySelectedReply() {
        guard let selectedDraft else { return }
        let trimmedReply = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            syncMessage = "Write or keep a reply before copying."
            return
        }

        let reply = GmailReplyComposer.replyDraft(for: selectedDraft, body: trimmedReply)
        PlatformServices.copyToPasteboard("Subject: \(reply.subject)\n\n\(reply.body)")
        updateSelected { draft in
            draft.replyStatus = .copied
        }
        persistCurrentState()
        syncMessage = "Copied reply to clipboard. Paste it into Gmail after reviewing."
    }

    func openSelectedReplyInGmailCompose() {
        guard let selectedDraft else { return }
        let trimmedReply = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            syncMessage = "Write or keep a suggested reply before opening Gmail compose."
            return
        }

        let reply = GmailReplyComposer.replyDraft(for: selectedDraft, body: trimmedReply)
        PlatformServices.open(GmailReplyComposer.composeURL(for: reply))
        updateSelected { draft in
            draft.replyStatus = .openedInGmail
        }
        syncMessage = "Opened Gmail compose for '\(selectedDraft.source.subject)'. Review and send it in Gmail."
    }

    func saveSelectedReplyAsGmailDraft() async {
        guard let selectedDraft else { return }
        let trimmedReply = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            syncMessage = "Write or keep a suggested reply before saving a Gmail draft."
            return
        }
        guard isGoogleConnected, let gmail = gmailDraftClientForReply() else {
            syncMessage = "Connect Google again with Gmail draft permission before saving replies to Gmail."
            return
        }

        isSavingGmailDraft = true
        syncMessage = selectedDraft.gmailReplyDraftID == nil ? "Saving Gmail draft..." : "Updating Gmail draft..."
        defer { isSavingGmailDraft = false }

        do {
            let reply = GmailReplyComposer.replyDraft(for: selectedDraft, body: trimmedReply)
            let reference = try await gmail.saveDraft(reply, existingDraftID: selectedDraft.gmailReplyDraftID)
            let wasExistingDraft = selectedDraft.gmailReplyDraftID != nil
            updateSelected { draft in
                draft.replyStatus = .savedToGmailDraft
                draft.gmailReplyDraftID = reference.id
                draft.lastError = nil
            }
            syncMessage = wasExistingDraft
                ? "Updated the Gmail draft. Open Gmail to review and send it."
                : "Saved a Gmail draft. Open Gmail to review and send it."
        } catch {
            recordGoogleReconnectIfNeeded(error.localizedDescription)
            lastGoogleError = error.localizedDescription
            syncMessage = "Gmail draft failed: \(error.localizedDescription). Reconnect Google if the compose permission is new."
        }
    }

    func openSelectedEmailInGmail() {
        guard let selectedDraft else { return }
        let query = selectedDraft.source.subject.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selectedDraft.source.subject
        guard let url = URL(string: "https://mail.google.com/mail/u/0/#search/\(query)") else {
            syncMessage = "Could not build a Gmail search URL for this email."
            return
        }

        PlatformServices.open(url)
        syncMessage = "Opened Gmail search for '\(selectedDraft.source.subject)'."
    }

    func openSelectedCalendarEvent() {
        guard let selectedDraft else { return }
        guard let eventURL = selectedDraft.googleEventURL else {
            syncMessage = "This item is not linked to a Google Calendar event yet."
            return
        }

        PlatformServices.open(eventURL)
        syncMessage = "Opened the Google Calendar event for '\(selectedDraft.title)'."
    }

    func openGoogleCalendar() {
        guard let calendarURL = URL(string: "https://calendar.google.com") else { return }
        PlatformServices.open(calendarURL)
        syncMessage = "Opened Google Calendar."
    }

    func importBankStatement(from url: URL) {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let transactions = try BankStatementCSVImporter.parse(data: data, source: url.lastPathComponent)
            let addedCount = localState.mergeBankTransactions(transactions)
            persistCurrentState()
            syncMessage = addedCount == 0
                ? "No new transactions were found. This statement was already imported."
                : "Imported " + String(addedCount) + " transaction(s). Review the suggested payment matches."
        } catch {
            syncMessage = "Statement import failed: " + error.localizedDescription
        }
    }

    func loadSampleBankTransactions() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let transactions = [
            BankTransaction(
                bookingDate: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                amount: Decimal(string: "-42.50")!,
                counterparty: "Water Company",
                description: "Monthly water bill",
                source: "Sample statement"
            ),
            BankTransaction(
                bookingDate: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                amount: Decimal(string: "-129.99")!,
                counterparty: "Insurance Services",
                description: "Household insurance renewal",
                source: "Sample statement"
            ),
            BankTransaction(
                bookingDate: calendar.date(byAdding: .day, value: -3, to: today) ?? today,
                amount: Decimal(string: "-18.75")!,
                counterparty: "Local Grocer",
                description: "Card payment",
                source: "Sample statement"
            )
        ]
        let addedCount = localState.mergeBankTransactions(transactions)
        persistCurrentState()
        syncMessage = addedCount == 0
            ? "Sample statement is already loaded."
            : "Loaded " + String(addedCount) + " sample transaction(s). Suggested matches are ready for review."
    }

    func bankMatch(for draft: InboxDraft) -> BankTransactionMatch? {
        localState.bankMatches
            .filter { $0.draftID == draft.id && $0.status == .confirmed }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func bankSuggestion(for draft: InboxDraft) -> BankMatchSuggestion? {
        bankingMatchSuggestions.first { $0.draftID == draft.id }
    }

    func bankTransaction(for id: UUID) -> BankTransaction? {
        localState.bankTransactions.first { $0.id == id }
    }

    func bankTransactionsForManualMatch(against draft: InboxDraft) -> [BankTransaction] {
        let confirmedTransactionIDs = Set(
            localState.bankMatches
                .filter { $0.status == .confirmed }
                .map(\.transactionID)
        )

        return localState.bankTransactions
            .filter { $0.isOutgoing && !confirmedTransactionIDs.contains($0.id) }
            .sorted { left, right in
                let leftDistance = bankAmountDistance(left.amount, expectedAmount: draft.amount)
                let rightDistance = bankAmountDistance(right.amount, expectedAmount: draft.amount)
                if leftDistance == rightDistance {
                    return left.bookingDate > right.bookingDate
                }
                return leftDistance < rightDistance
            }
            .prefix(8)
            .map { $0 }
    }

    func confirmBankMatch(draftID: UUID, transactionID: UUID, confidence: Double) {
        guard let draft = model.drafts.first(where: { $0.id == draftID }),
              let transaction = bankTransaction(for: transactionID) else {
            syncMessage = "That payment or household item is no longer available."
            return
        }

        localState.saveBankMatch(
            BankTransactionMatch(
                draftID: draftID,
                transactionID: transactionID,
                confidence: confidence,
                status: .confirmed
            )
        )
        persistCurrentState()
        syncMessage = "Matched " + transaction.displayName + " to '" + draft.title + "'. This is read-only; complete any remaining task separately."
    }

    func dismissBankMatch(draftID: UUID, transactionID: UUID) {
        guard bankTransaction(for: transactionID) != nil else { return }
        localState.saveBankMatch(
            BankTransactionMatch(
                draftID: draftID,
                transactionID: transactionID,
                confidence: 0,
                status: .dismissed
            )
        )
        persistCurrentState()
        syncMessage = "Dismissed that payment suggestion."
    }

    private var visibleDrafts: [InboxDraft] {
        model.drafts.filter {
            !($0.triageState?.isClosed ?? false)
                && !DraftSnoozeService.isCurrentlySnoozed($0, now: activeWorkNow)
        }
    }

    private var shouldBlockGoogleDemoFallback: Bool {
        !isGoogleConnected
            && !lastGoogleError.isEmpty
            && !googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recordGoogleReconnectIfNeeded(_ errorMessage: String?) {
        guard let errorMessage, !errorMessage.isEmpty else { return }
        let requiresReconnect = errorMessage.localizedCaseInsensitiveContains("invalid_grant")
            || errorMessage.localizedCaseInsensitiveContains("token refresh failed")
            || errorMessage.localizedCaseInsensitiveContains("missingstoredtokens")

        guard requiresReconnect else { return }
        isGoogleConnected = false
        lastGoogleError = errorMessage
        googleConnectionStatus = "Reconnect Google to restore Gmail and Calendar access."
    }

    private func bankAmountDistance(_ transactionAmount: Decimal, expectedAmount: Decimal?) -> Decimal {
        guard let expectedAmount else { return 0 }
        let actual = transactionAmount < 0 ? -transactionAmount : transactionAmount
        let expected = expectedAmount < 0 ? -expectedAmount : expectedAmount
        let distance = actual - expected
        return distance < 0 ? -distance : distance
    }

    private func updateSelected(_ mutate: (inout InboxDraft) -> Void) {
        guard var draft = selectedDraft else { return }
        mutate(&draft)
        model.replaceDraft(draft)
        persistCurrentState()
    }

    private func markCalendarUpdateRequiredIfNeeded(_ draft: inout InboxDraft) {
        guard draft.status == .approved, draft.googleEventID != nil else { return }
        draft.status = .calendarUpdateRequired
        draft.lastError = "Local edits need to be synced to the existing Google Calendar event."
    }

    private func refreshEditorFields() {
        titleDraft = selectedDraft?.title ?? ""
        dueDateDraft = selectedDraft?.dueDate ?? Date()
        if let amount = selectedDraft?.amount {
            amountDraft = "\(amount)"
        } else {
            amountDraft = ""
        }

        if let selectedDraft {
            if let savedReply = localState.replyText(for: selectedDraft.id) {
                replyDraft = savedReply
            } else if let reply = intelligence(for: selectedDraft).suggestedReply {
                replyDraft = reply.body
            } else {
                replyDraft = ""
            }
        } else {
            replyDraft = ""
        }
    }

    private func persistCurrentState(saveCurrentReply: Bool = true) {
        localState.drafts = model.drafts
        if saveCurrentReply, let selectedDraft, !replyDraft.isEmpty {
            localState.setReplyText(replyDraft, for: selectedDraft.id)
        }

        do {
            try localStore.save(localState)
        } catch {
            syncMessage = "Local save failed: \(error.localizedDescription)"
        }

        scheduleLocalReminderRefresh()
    }

    private func scheduleLocalReminderRefresh() {
        localReminderRefreshTask?.cancel()
        localReminderRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refreshLocalReminderNotifications()
        }
    }

    private func startActiveWorkClock() {
        activeWorkRefreshTask?.cancel()
        activeWorkRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.activeWorkNow = Date()
                await self.refreshLocalReminderNotifications()
            }
        }
    }

    private func resetManualItemFields() {
        newItemTitle = ""
        newItemAmount = ""
        newItemHasDueDate = true
        newItemRecurrence = nil
    }

    private func gmailClientForImport() -> GmailClient {
        guard isGoogleConnected else {
            return demoGmail
        }

        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            return demoGmail
        }

        return GoogleGmailAPIClient(
            tokenProvider: googleAccessTokenProvider(clientID: clientID)
        )
    }

    private func gmailDraftClientForReply() -> GmailDraftClient? {
        guard isGoogleConnected else { return nil }

        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { return nil }

        return GoogleGmailAPIClient(
            tokenProvider: googleAccessTokenProvider(clientID: clientID)
        )
    }

    private func approvalServiceForCurrentConnection() -> HouseholdApprovalService {
        HouseholdApprovalService(
            calendar: calendarClientForApproval(),
            appBaseURL: appBaseURL
        )
    }

    private func calendarClientForApproval() -> CalendarClient {
        guard isGoogleConnected else {
            return DemoCalendarClient()
        }

        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            return DemoCalendarClient()
        }

        return GoogleCalendarAPIClient(
            tokenProvider: googleAccessTokenProvider(clientID: clientID),
            calendarID: normalizedGoogleCalendarID()
        )
    }

    private func householdForApproval() -> HouseholdContext {
        guard isGoogleConnected else {
            return household
        }

        return HouseholdContext(
            id: household.id,
            members: household.members,
            areas: household.areas,
            sharedCalendarID: normalizedGoogleCalendarID()
        )
    }

    private func normalizedGoogleCalendarID() -> String {
        let trimmed = googleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendarID = trimmed.isEmpty ? "primary" : trimmed
        UserDefaults.standard.set(calendarID, forKey: Self.googleCalendarIDDefaultsKey)
        return calendarID
    }

    private func effectiveGoogleClientSecret() -> String? {
        #if os(iOS)
        return nil
        #else
        let trimmed = googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return try? googleTokenStore.load()?.clientSecret
        #endif
    }

    private func googleAccessTokenProvider(clientID: String) -> GoogleAccessTokenProvider {
        #if os(iOS)
        GoogleMobileAccessTokenProvider()
        #else
        GoogleKeychainAccessTokenProvider(
            clientID: clientID,
            clientSecret: effectiveGoogleClientSecret(),
            tokenStore: googleTokenStore
        )
        #endif
    }

    private var googleClientIDRequirement: String {
        #if os(iOS)
        "Paste the iOS app client ID first."
        #else
        "Paste your Desktop app client ID first."
        #endif
    }

    private static func defaultLocalStoreURL() -> URL {
        let baseURL: URL
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = applicationSupport
        } else {
            #if os(macOS)
            baseURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            #else
            baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            #endif
        }

        return baseURL
            .appendingPathComponent("HouseholdCommandCenter", isDirectory: true)
            .appendingPathComponent("local-state.json")
    }

    private static var bundledGoogleClientID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}

struct CalendarReminderGroup: Identifiable {
    var id: CalendarReadinessState { state }
    var state: CalendarReadinessState
    var drafts: [InboxDraft]
}

private extension CalendarReadinessState {
    static let reminderOrder: [CalendarReadinessState] = [
        .retryRequired,
        .updateRequired,
        .externalChange,
        .needsDueDate,
        .readyToApprove,
        .scheduled
    ]
}

private extension Array where Element == InboxDraft {
    func sortedByCalendarReadiness() -> [InboxDraft] {
        sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case (.some(let lhsDueDate), .some(let rhsDueDate)):
                return lhsDueDate < rhsDueDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.source.receivedAt > rhs.source.receivedAt
            }
        }
    }
}

enum HouseholdSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case inbox = "Inbox"
    case bills = "Bills"
    case reminders = "Reminders"
    case review = "Review"
    case banking = "Banking"
    case areas = "Areas"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today:
            "sun.max"
        case .inbox:
            "tray.full"
        case .bills:
            "creditcard"
        case .reminders:
            "bell.badge"
        case .review:
            "checklist"
        case .banking:
            "building.columns"
        case .areas:
            "folder"
        case .settings:
            "gearshape"
        }
    }

    var mobileTitle: String {
        switch self {
        case .today:
            "Today"
        case .inbox:
            "Inbox"
        case .bills:
            "Bills"
        case .reminders:
            "Calendar"
        case .areas:
            "Household"
        case .review:
            "Review"
        case .banking:
            "Banking"
        case .settings:
            "Settings"
        }
    }

    var mobileSystemImage: String {
        switch self {
        case .today:
            "circle.fill"
        case .inbox:
            "tray"
        case .bills:
            "dollarsign"
        case .reminders:
            "calendar"
        case .areas:
            "house.fill"
        case .review:
            "checklist"
        case .banking:
            "building.columns"
        case .settings:
            "gearshape"
        }
    }
}

private struct DemoGmailClient: GmailClient {
    private let messages: [SourceEmail]

    init(messages: [SourceEmail]) {
        self.messages = messages
    }

    func messages(labeled label: String) async throws -> [SourceEmail] {
        messages.filter { $0.label == label }
    }
}

private struct DemoEmailExtractor: EmailExtractor {
    private let resultsByMessageID: [String: ExtractionResult]
    private let fallback = HouseholdHeuristicEmailExtractor()

    init(resultsByMessageID: [String: ExtractionResult]) {
        self.resultsByMessageID = resultsByMessageID
    }

    func extract(from email: SourceEmail, household: HouseholdContext) async throws -> ExtractionResult {
        if let result = resultsByMessageID[email.gmailMessageID] {
            return result
        }

        return try await fallback.extract(from: email, household: household)
    }
}

private struct DemoCalendarClient: CalendarClient {
    func createEvent(_ event: CalendarEventDraft) async throws -> CalendarEventReference {
        let slug = event.title.lowercased().filter { $0.isLetter || $0.isNumber }
        return CalendarEventReference(
            id: "demo-\(slug)-\(Int(event.dueDate.timeIntervalSince1970))",
            url: URL(string: "https://calendar.google.com/calendar/event?eid=\(slug)")
        )
    }

    func updateEvent(id eventID: String, with event: CalendarEventDraft) async throws -> CalendarEventReference {
        let slug = event.title.lowercased().filter { $0.isLetter || $0.isNumber }
        return CalendarEventReference(
            id: eventID,
            url: URL(string: "https://calendar.google.com/calendar/event?eid=\(slug)")
        )
    }

    func eventStatus(for eventID: String) async throws -> CalendarEventSyncState {
        .present
    }
}

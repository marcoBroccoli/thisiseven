import AppKit
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

    let household: HouseholdContext
    let gmailLabel = "HouseholdTodo"

    private let demoGmail: GmailClient
    private let extractor: EmailExtractor
    private let intelligenceAnalyzer = EmailIntelligenceAnalyzer()
    private let localStore: HouseholdLocalStore
    private let googleTokenStore = GoogleKeychainTokenStore()
    private let appBaseURL = URL(string: "household://drafts")!
    private var localState: LocalHouseholdState
    private static let googleClientIDDefaultsKey = "HouseholdCommandCenter.GoogleClientID"
    private static let googleCalendarIDDefaultsKey = "HouseholdCommandCenter.GoogleCalendarID"

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
        self.googleClientID = UserDefaults.standard.string(forKey: Self.googleClientIDDefaultsKey) ?? ""
        self.googleCalendarID = UserDefaults.standard.string(forKey: Self.googleCalendarIDDefaultsKey) ?? "primary"
        refreshEditorFields()
        refreshGoogleConnectionStatus()
    }

    var selectedDraft: InboxDraft? {
        model.selectedDraft
    }

    var dashboard: HouseholdDashboard {
        HouseholdDashboard(household: household, drafts: model.drafts, now: Date())
    }

    var triageBuckets: [InboxTriageBucket] {
        model.triageBuckets(household: household, now: Date())
    }

    var todaySections: [TodayReviewSection] {
        TodayReviewModel(drafts: model.drafts, household: household, now: Date()).sections
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
            syncMessage = "Import failed from \(importMode): \(error.localizedDescription)"
        }
    }

    func connectGoogle() async {
        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = effectiveGoogleClientSecret()
        let calendarID = normalizedGoogleCalendarID()
        guard !clientID.isEmpty else {
            googleConnectionStatus = "Paste your Desktop app client ID first."
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
        } catch {
            isGoogleConnected = false
            lastGoogleError = error.localizedDescription
            googleConnectionStatus = "Google connection failed: \(error.localizedDescription)"
            syncMessage = googleConnectionStatus
        }
    }

    func disconnectGoogle() {
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
    }

    func refreshGoogleConnectionStatus() {
        do {
            if let tokens = try googleTokenStore.load() {
                if googleClientID.isEmpty {
                    googleClientID = tokens.clientID
                }
                if googleClientSecret.isEmpty {
                    googleClientSecret = tokens.clientSecret ?? ""
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
    }

    func approveSelectedDraft() async {
        guard let selectedDraft else { return }
        if selectedDraft.status == .calendarUpdateRequired, selectedDraft.googleEventID != nil {
            await syncSelectedCalendarUpdate()
            return
        }

        let approvalMode = isGoogleConnected ? "Google Calendar \(normalizedGoogleCalendarID())" : "demo Calendar"
        syncMessage = "Creating event in \(approvalMode)..."
        let service = approvalServiceForCurrentConnection()
        let readiness = calendarReadiness(for: selectedDraft)
        let approved = await service.approve(
            selectedDraft,
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
            syncMessage = "Calendar write needs retry: \(approved.lastError ?? "Unknown error")."
        default:
            syncMessage = "Draft moved to \(approved.status.rawValue)."
        }
    }

    func rejectSelectedDraft() {
        guard let selectedDraft else { return }
        let rejected = approvalServiceForCurrentConnection().reject(selectedDraft, reason: "Rejected from Mac approval queue.")
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
        }
        if selectedDraft.googleEventID != nil {
            syncMessage = "Marked '\(selectedDraft.title)' done locally. Its Calendar event remains as a record."
        } else {
            syncMessage = "Marked '\(selectedDraft.title)' done locally."
        }
    }

    func snoozeSelected(byDays days: Int) {
        guard days > 0, let selectedDraft else { return }
        let baseDate = max(selectedDraft.dueDate ?? Date(), Date())
        let newDueDate = Calendar.current.date(byAdding: .day, value: days, to: baseDate)
            ?? baseDate.addingTimeInterval(TimeInterval(days) * 86_400)

        updateSelected { draft in
            draft.dueDate = newDueDate
            draft.triageState = .active
            markCalendarUpdateRequiredIfNeeded(&draft)
        }
        dueDateDraft = newDueDate
        syncMessage = selectedDraft.googleEventID == nil
            ? "Snoozed '\(selectedDraft.title)' by \(days) day\(days == 1 ? "" : "s")."
            : "Snoozed '\(selectedDraft.title)'. Sync the Calendar update when ready."
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
            let reconciled = await service.reconcileCalendarState(for: draft)
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
        let draft = ManualDraftFactory.makeDraft(
            title: trimmedTitle,
            dueDate: hasDueDate ? newItemDueDate : nil,
            amount: amount,
            ownerID: UUID(uuidString: newItemOwnerID),
            areaID: UUID(uuidString: newItemAreaID)
        )

        model.replaceDraft(draft)
        model.selectDraft(id: draft.id)
        selectedSection = .inbox
        refreshEditorFields()
        resetManualItemFields()
        persistCurrentState()
        syncMessage = hasDueDate
            ? "Created '\(trimmedTitle)'. Review it, then approve it to Google Calendar."
            : "Created '\(trimmedTitle)' without a due date. Add one when it becomes schedulable."
    }

    func beginManualItem() {
        resetManualItemFields()
        newItemHasDueDate = true
        newItemDueDate = Date().addingTimeInterval(86_400)
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Subject: \(reply.subject)\n\n\(reply.body)", forType: .string)
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
        NSWorkspace.shared.open(GmailReplyComposer.composeURL(for: reply))
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

        NSWorkspace.shared.open(url)
        syncMessage = "Opened Gmail search for '\(selectedDraft.source.subject)'."
    }

    func openSelectedCalendarEvent() {
        guard let selectedDraft else { return }
        guard let eventURL = selectedDraft.googleEventURL else {
            syncMessage = "This item is not linked to a Google Calendar event yet."
            return
        }

        NSWorkspace.shared.open(eventURL)
        syncMessage = "Opened the Google Calendar event for '\(selectedDraft.title)'."
    }

    func openGoogleCalendar() {
        guard let calendarURL = URL(string: "https://calendar.google.com") else { return }
        NSWorkspace.shared.open(calendarURL)
        syncMessage = "Opened Google Calendar."
    }

    private var visibleDrafts: [InboxDraft] {
        model.drafts.filter { !($0.triageState?.isClosed ?? false) }
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
    }

    private func resetManualItemFields() {
        newItemTitle = ""
        newItemAmount = ""
        newItemHasDueDate = true
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
            tokenProvider: GoogleKeychainAccessTokenProvider(
                clientID: clientID,
                clientSecret: effectiveGoogleClientSecret(),
                tokenStore: googleTokenStore
            )
        )
    }

    private func gmailDraftClientForReply() -> GmailDraftClient? {
        guard isGoogleConnected else { return nil }

        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { return nil }

        return GoogleGmailAPIClient(
            tokenProvider: GoogleKeychainAccessTokenProvider(
                clientID: clientID,
                clientSecret: effectiveGoogleClientSecret(),
                tokenStore: googleTokenStore
            )
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
            tokenProvider: GoogleKeychainAccessTokenProvider(
                clientID: clientID,
                clientSecret: effectiveGoogleClientSecret(),
                tokenStore: googleTokenStore
            ),
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
        let trimmed = googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return try? googleTokenStore.load()?.clientSecret
    }

    private static func defaultLocalStoreURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("HouseholdCommandCenter", isDirectory: true)
            .appendingPathComponent("local-state.json")
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

import SwiftUI
import UniformTypeIdentifiers
import EvenCore
import HouseholdCore
#if canImport(UIKit)
import UIKit
#endif

/// The household's single working surface. Email can suggest a todo, Calendar
/// can schedule a dated todo, but the couple always manages one list.
struct TodosView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case review = "Review"
        case open = "To do"
        case done = "Done"

        var id: String { rawValue }
    }

    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var filter: Filter = .all
    @State private var reviewing: Draft?
    @State private var showQuickAdd = false
    @State private var showSources = false
    @State private var showCompleted = false

    private var visibleTodos: [TodoItem] {
        switch filter {
        case .all: return model.todos
        case .review:
            return model.todos.filter {
                $0.state == .needsReview || $0.task?.calendarSyncState?.requiresResolution == true
            }
        case .open: return model.todos.filter { $0.state == .open }
        case .done: return model.todos.filter { $0.state == .done }
        }
    }

    private var reviewTodos: [TodoItem] { visibleTodos.filter { $0.state == .needsReview } }
    private var calendarReviewTodos: [TodoItem] {
        visibleTodos.filter { $0.task?.calendarSyncState?.requiresResolution == true }
    }
    private var openTodos: [TodoItem] {
        let calendarReviewIDs = Set(calendarReviewTodos.map(\.id))
        return visibleTodos.filter { $0.state == .open && !calendarReviewIDs.contains($0.id) }
    }
    private var doneTodos: [TodoItem] { visibleTodos.filter { $0.state == .done } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                sourceRail
                filters

                if model.isLoading && model.summary == nil {
                    ProgressView().tint(palette.sub)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 76)
                } else if visibleTodos.isEmpty {
                    emptyState
                } else {
                    todoSections
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .animation(.easeOut(duration: 0.25), value: model.todos.map(\.id))
            .animation(.easeOut(duration: 0.2), value: filter)
        }
        .refreshable { await model.refreshAll() }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.bg)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(palette.ink).shadow(color: .black.opacity(0.16), radius: 10, y: 5))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .accessibilityIdentifier("fab-add-task")
            .accessibilityLabel("Add todo")
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .sheet(item: $reviewing) { draft in
            DraftReviewSheet(model: model, draft: draft)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet(model: model)
        }
        .sheet(isPresented: $showSources) {
            TodoSourcesSheet(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenHeader(kicker: "SHARED HOUSEHOLD", title: "Todos", subtitle: "One list for everything that needs doing.")
            Spacer(minLength: 0)
            Button {
                showSources = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(palette.line, lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .accessibilityIdentifier("todo-sources")
            .accessibilityLabel("Manage Gmail and Calendar")
            .padding(.top, 2)
        }
    }

    private var sourceRail: some View {
        HStack(spacing: 8) {
            SourceIndicator(symbol: "envelope", title: "Gmail",
                            value: model.googleStatus?.connected == true
                                ? "\(model.pendingReviewCount) to review" : "Not connected",
                            tint: palette.clay) {
                showSources = true
            }
            SourceIndicator(symbol: "calendar", title: "Calendar",
                            value: calendarSourceLabel,
                            tint: palette.teal) {
                showSources = true
            }
        }
        .padding(.top, 14)
    }

    private var calendarSourceLabel: String {
        if model.calendarSyncing { return "Syncing..." }
        if model.calendarIssueCount > 0 { return "\(model.calendarIssueCount) to review" }
        if let status = model.googleStatus?.calendarLastSyncAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: status, relativeTo: Date()))"
        }
        return "\(model.scheduledTodoCount) scheduled"
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases) { option in
                    SelectPill(label: option.rawValue.uppercased(), selected: filter == option) {
                        filter = option
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var todoSections: some View {
        if !reviewTodos.isEmpty {
            sectionHeader("NEEDS REVIEW", count: reviewTodos.count)
            VStack(spacing: 9) {
                ForEach(reviewTodos) { item in
                    if let draft = item.draft {
                        SuggestedTodoRow(model: model, draft: draft) { reviewing = draft }
                    }
                }
            }
        }

        if !calendarReviewTodos.isEmpty {
            sectionHeader("CALENDAR NEEDS REVIEW", count: calendarReviewTodos.count)
                .padding(.top, reviewTodos.isEmpty ? 0 : 18)
            VStack(spacing: 9) {
                ForEach(calendarReviewTodos) { item in
                    if let task = item.task {
                        CalendarReviewCard(model: model, task: task)
                    }
                }
            }
        }

        if !openTodos.isEmpty {
            sectionHeader("TO DO", count: openTodos.count)
                .padding(.top, (reviewTodos.isEmpty && calendarReviewTodos.isEmpty) ? 0 : 18)
            ForEach(openTodos) { item in
                if let task = item.task {
                    TaskRow(model: model, task: task)
                }
            }
        }

        if !doneTodos.isEmpty {
            Button {
                showCompleted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("COMPLETED · \(doneTodos.count)")
                        .capsLabel(9.5, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.sub)
                        .rotationEffect(.degrees(showCompleted ? 0 : -90))
                }
                .padding(.top, (reviewTodos.isEmpty && calendarReviewTodos.isEmpty && openTodos.isEmpty) ? 0 : 18)
                .padding(.bottom, showCompleted ? 2 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))

            if showCompleted {
                ForEach(doneTodos) { item in
                    if let task = item.task {
                        TaskRow(model: model, task: task)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .capsLabel(9.5, tracking: 1.4)
            .foregroundStyle(palette.sub)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(palette.sub)
            Text(emptyTitle)
                .font(EvenFont.serif(17, italic: true))
                .foregroundStyle(palette.ink)
            Text("Add a todo or check Gmail for something to review.")
                .font(EvenFont.serif(12.5, italic: true))
                .foregroundStyle(palette.sub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "Nothing needs you right now."
        case .review: return "Nothing waiting for review."
        case .open: return "Your list is clear."
        case .done: return "Nothing completed this week."
        }
    }
}

private struct SourceIndicator: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    let value: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(tint.opacity(0.13)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased())
                        .capsLabel(8.5, tracking: 0.8, weight: .bold)
                        .foregroundStyle(palette.ink)
                    Text(value)
                        .font(EvenFont.sans(10.5, .regular))
                        .foregroundStyle(palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }
}

private struct SuggestedTodoRow: View {
    @Bindable var model: AppModel
    let draft: Draft
    let open: () -> Void
    @Environment(\.palette) private var palette

    private var urgency: String {
        ["LOW", "MEDIUM", "HIGH"][max(0, min(2, draft.urgency - 1))]
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "envelope")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.clay)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.clay.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(draft.isFromGmail ? "GMAIL" : "SUGGESTED")
                            .capsLabel(8.5, tracking: 0.8, weight: .bold)
                            .foregroundStyle(palette.clay)
                        if draft.urgency == 3 {
                            Text(urgency)
                                .capsLabel(8.5, tracking: 0.8, weight: .bold)
                                .foregroundStyle(palette.ink)
                        }
                    }
                    Text(draft.title.isEmpty ? draft.subject : draft.title)
                        .font(EvenFont.serif(15))
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.leading)
                    if let summary = draft.summary ?? draft.sourcePreview, !summary.isEmpty {
                        Text(summary)
                            .font(EvenFont.serif(11.5, italic: true))
                            .foregroundStyle(palette.sub)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(metaLine)
                        .capsLabel(8.5, tracking: 0.5)
                        .foregroundStyle(palette.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.sub)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityIdentifier("draft-card-\(draft.subject)")
        .accessibilityLabel("Review suggested todo: \(draft.title.isEmpty ? draft.subject : draft.title)")
    }

    private var metaLine: String {
        var parts: [String] = []
        if let owner = model.member(draft.ownerMemberId) { parts.append(owner.displayName.uppercased()) }
        if let cents = draft.amountCents { parts.append(EvenFormat.euros(cents)) }
        if let due = draft.dueOn { parts.append("DUE \(EvenFormat.capsDate(due))") }
        return parts.isEmpty ? "TAP TO REVIEW" : parts.joined(separator: " · ")
    }
}

private struct CalendarReviewCard: View {
    @Bindable var model: AppModel
    let task: HouseholdTask
    @Environment(\.palette) private var palette
    @State private var confirmArchive = false

    private var state: CalendarSyncState { task.calendarSyncState ?? .notScheduled }
    private var isResolving: Bool { model.resolvingCalendarTaskID == task.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.teal)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.teal.opacity(0.13)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(heading.uppercased())
                        .capsLabel(8.5, tracking: 0.8, weight: .bold)
                        .foregroundStyle(palette.teal)
                    Text(task.title)
                        .font(EvenFont.serif(15))
                        .foregroundStyle(palette.ink)
                    Text(detail)
                        .font(EvenFont.sans(11, .regular))
                        .foregroundStyle(palette.sub)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }

            actions
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.teal.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("calendar-review-\(task.id.uuidString.lowercased())")
        .confirmationDialog("Archive this todo?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive todo", role: .destructive) {
                Task { await model.archive(task) }
            }
        } message: {
            Text("It will be removed from the household list. The Calendar event was already removed.")
        }
    }

    private var heading: String {
        switch state {
        case .externalChanged: return "Updated in Calendar"
        case .externalDeleted: return "Removed in Calendar"
        case .retryRequired: return "Calendar needs retry"
        case .notScheduled, .synced: return "Calendar review"
        }
    }

    private var detail: String {
        if let message = task.calendarLastError, !message.isEmpty { return message }
        switch state {
        case .externalChanged:
            return "The updated title or date is already reflected in this todo. Confirm when you have seen it."
        case .externalDeleted:
            return "Keep this todo to create a new event in the shared Calendar, or archive it here."
        case .retryRequired:
            return "Even could not finish the last Calendar change. Retry when the connection is ready."
        case .notScheduled, .synced:
            return ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .externalChanged:
            GhostButton(title: isResolving ? "Confirming…" : "Mark seen") {
                resolve(.acknowledge)
            }
            .disabled(isResolving)

        case .externalDeleted:
            HStack(spacing: 8) {
                GhostButton(title: isResolving ? "Restoring…" : "Restore to Calendar") {
                    resolve(.restore)
                }
                .disabled(isResolving)

                Button {
                    confirmArchive = true
                } label: {
                    Text("Archive")
                        .font(EvenFont.serif(15))
                        .foregroundStyle(palette.clay)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.clay.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(isResolving)
            }

        case .retryRequired:
            GhostButton(title: isResolving ? "Retrying…" : "Retry Calendar") {
                resolve(.retry)
            }
            .disabled(isResolving)

        case .notScheduled, .synced:
            EmptyView()
        }
    }

    private func resolve(_ action: EvenAPIClient.CalendarResolutionAction) {
        Task { _ = await model.resolveCalendarIssue(task, action: action) }
    }
}

private struct TodoSourcesSheet: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var showPayments = false

    var body: some View {
        SheetChrome(title: "TODO SOURCES") {
            if model.googleStatus?.connected == true {
                sourceSection(symbol: "envelope", title: "GMAIL", tint: palette.clay) {
                    Text(model.googleStatus?.email ?? "Connected")
                        .font(EvenFont.serif(14, italic: true))
                        .foregroundStyle(palette.ink)
                    GhostButton(title: model.gmailSyncing ? "Syncing…" : "Sync Gmail") {
                        Task { await model.syncGmail() }
                    }
                    .disabled(model.gmailSyncing)
                    .padding(.top, 4)
                }

                sourceSection(symbol: "calendar", title: "GOOGLE CALENDAR", tint: palette.teal) {
                    Text(calendarStatus)
                        .font(EvenFont.serif(14, italic: true))
                        .foregroundStyle(palette.ink)
                    if model.calendarInfo?.shared == true {
                        GhostButton(title: model.calendarSyncing ? "Syncing…" : "Sync Calendar") {
                            Task { await model.syncCalendar() }
                        }
                        .disabled(model.calendarSyncing)
                        .padding(.top, 4)
                    }
                    if let urlString = model.calendarInfo?.shareUrl, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Open shared calendar", systemImage: "arrow.up.right.square")
                                .font(EvenFont.sans(12, .semibold))
                                .foregroundStyle(palette.teal)
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                GoogleConnectCard(model: model)
            }

            sourceSection(symbol: "building.columns", title: "PAYMENTS", tint: palette.clay) {
                Text("Import a bank CSV and match it to unpaid household amounts. The statement stays on this phone.")
                    .font(EvenFont.sans(10.5, .regular))
                    .foregroundStyle(palette.sub)
                    .lineSpacing(2)
                GhostButton(title: "Review payments") {
                    showPayments = true
                }
                .padding(.top, 4)
            }

            sourceSection(symbol: "bell", title: "PHONE REMINDERS", tint: palette.ink) {
                Text(model.todoReminderStatus.statusText)
                    .font(EvenFont.serif(14, italic: true))
                    .foregroundStyle(palette.ink)

                phoneReminderControl

                Text("Dated todos get a quiet 9 AM nudge on this phone. Google Calendar keeps the shared reminders.")
                    .font(EvenFont.sans(10.5, .regular))
                    .foregroundStyle(palette.sub)
                    .lineSpacing(2)
            }
        }
        .sheet(isPresented: $showPayments) {
            LocalStatementSheet(model: model)
        }
        .task {
            await model.refreshTodoReminders()
            if model.googleStatus?.connected == true {
                await model.loadCalendar(month: Date())
            }
        }
    }

    private var calendarStatus: String {
        if model.calendarInfo?.shared == true {
            return "Shared calendar is ready. Direct edits become todos here."
        }
        return "Add a due date to a todo to create the shared calendar."
    }

    @ViewBuilder
    private var phoneReminderControl: some View {
        switch model.todoReminderStatus {
        case .needsPermission:
            GhostButton(title: model.todoReminderScheduling ? "Turning on…" : "Turn on reminders") {
                Task { await model.enableTodoReminders() }
            }
            .disabled(model.todoReminderScheduling)
            .padding(.top, 4)
        case .denied:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                Link(destination: url) {
                    Label("Open iPhone Settings", systemImage: "gear")
                        .font(EvenFont.sans(12, .semibold))
                        .foregroundStyle(palette.clay)
                }
                .padding(.top, 4)
            }
            #endif
        case .scheduled, .unavailable:
            GhostButton(title: model.todoReminderScheduling ? "Updating…" : "Refresh reminders") {
                Task { await model.refreshTodoReminders() }
            }
            .disabled(model.todoReminderScheduling)
            .padding(.top, 4)
        }
    }

    private func sourceSection<Content: View>(symbol: String, title: String, tint: Color,
                                               @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).capsLabel(9, tracking: 1.3).foregroundStyle(palette.sub)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.faint))
    }
}

private struct LocalStatementSheet: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var store = LocalStatementStore()
    @State private var importing = false
    @State private var importError: String?
    @State private var confirmClear = false

    private var paymentDrafts: [Draft] {
        model.drafts.filter { ($0.amountCents ?? 0) > 0 && $0.status == .pending }
    }

    private var suggestions: [BankPaymentMatchSuggestion] {
        store.suggestions(for: model.drafts)
    }

    var body: some View {
        SheetChrome(title: "PAYMENTS") {
            Text("Read-only statement matching")
                .font(EvenFont.serif(18, italic: true))
                .foregroundStyle(palette.ink)

            Text("Import a CSV export from your bank. Even keeps the statement and your match decisions on this phone; it never signs in to a bank or initiates a payment.")
                .font(EvenFont.sans(11, .regular))
                .foregroundStyle(palette.sub)
                .lineSpacing(2)

            HStack(spacing: 8) {
                paymentMetric(value: store.transactions.count, title: "IMPORTED")
                paymentMetric(value: suggestions.count, title: "TO REVIEW")
                paymentMetric(value: store.confirmedMatchCount, title: "MATCHED")
            }
            .padding(.vertical, 2)

            GhostButton(title: importing ? "Importing…" : "Import bank CSV") {
                importing = true
            }
            .disabled(importing)

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(EvenFont.sans(11, .semibold))
                    .foregroundStyle(palette.clay)
            }

            if paymentDrafts.isEmpty {
                paymentEmptyState(
                    "No unpaid amounts to match",
                    "Email suggestions with an amount appear here before they are approved."
                )
            } else if suggestions.isEmpty {
                paymentEmptyState(
                    store.transactions.isEmpty ? "Import a statement to start" : "No confident payment matches",
                    store.transactions.isEmpty
                        ? "Choose a CSV exported from your bank."
                        : "The remaining transactions do not closely match an open household amount."
                )
            } else {
                Text("SUGGESTED MATCHES · \(suggestions.count)")
                    .capsLabel(9.5, tracking: 1.4)
                    .foregroundStyle(palette.sub)
                    .padding(.top, 4)
                ForEach(suggestions) { suggestion in
                    if let draft = paymentDrafts.first(where: { $0.id == suggestion.obligationID }),
                       let transaction = store.transaction(id: suggestion.transactionID) {
                        StatementMatchCard(draft: draft, transaction: transaction, suggestion: suggestion,
                                           confirm: { resolvePayment(suggestion, asConfirmed: true) },
                                           dismiss: { resolvePayment(suggestion, asConfirmed: false) })
                    }
                }
            }

            if !store.outgoingTransactions.isEmpty {
                HStack {
                    Text("IMPORTED PAYMENTS")
                        .capsLabel(9.5, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                    Spacer()
                    Text("\(store.unmatchedOutgoingCount) UNMATCHED")
                        .capsLabel(8.5, tracking: 0.8)
                        .foregroundStyle(palette.sub)
                }
                .padding(.top, 8)

                ForEach(store.outgoingTransactions.prefix(6)) { transaction in
                    StatementTransactionRow(transaction: transaction)
                }
            }

            if store.lastImportAt != nil {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear local statement", systemImage: "trash")
                        .font(EvenFont.sans(11.5, .semibold))
                        .foregroundStyle(palette.clay)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 5)
                }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importing = false
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let added = try store.importStatement(data: Data(contentsOf: url), source: url.lastPathComponent)
                    importError = nil
                    model.stamp(added == 0 ? "STATEMENT — NO NEW PAYMENTS" : "STATEMENT — \(added) IMPORTED")
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? "The statement could not be imported."
                }
            case let .failure(error):
                importError = error.localizedDescription
            }
        }
        .confirmationDialog("Clear this local statement?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear statement", role: .destructive) {
                do {
                    try store.clear()
                    model.stamp("LOCAL STATEMENT CLEARED")
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription
                        ?? "The local statement could not be cleared."
                }
            }
        } message: {
            Text("Imported transactions and local payment decisions will be removed from this phone. Household todos and email remain unchanged.")
        }
    }

    private func paymentMetric(value: Int, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(EvenFont.serif(20, .medium))
                .foregroundStyle(palette.ink)
            Text(title)
                .capsLabel(8, tracking: 0.7)
                .foregroundStyle(palette.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.faint))
    }

    private func paymentEmptyState(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.ink)
            Text(detail)
                .font(EvenFont.sans(11, .regular))
                .foregroundStyle(palette.sub)
                .lineSpacing(2)
        }
        .padding(.vertical, 8)
    }

    private func resolvePayment(_ suggestion: BankPaymentMatchSuggestion, asConfirmed: Bool) {
        do {
            if asConfirmed {
                try store.confirm(suggestion)
                model.stamp("PAYMENT CONFIRMED")
            } else {
                try store.dismiss(suggestion)
                model.stamp("PAYMENT DISMISSED")
            }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription
                ?? "The payment decision could not be saved."
        }
    }
}

private struct StatementMatchCard: View {
    let draft: Draft
    let transaction: BankTransaction
    let suggestion: BankPaymentMatchSuggestion
    let confirm: () -> Void
    let dismiss: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.clay)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(palette.clay.opacity(0.13)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.title.isEmpty ? draft.subject : draft.title)
                        .font(EvenFont.serif(15))
                        .foregroundStyle(palette.ink)
                    Text("\(currency(draft.amountCents ?? 0)) · \(transaction.displayName)")
                        .font(EvenFont.sans(11, .regular))
                        .foregroundStyle(palette.sub)
                    Text(suggestion.reasons.joined(separator: " · "))
                        .font(EvenFont.sans(10.5, .regular))
                        .foregroundStyle(palette.sub)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("\(Int((suggestion.confidence * 100).rounded()))%")
                    .capsLabel(9, tracking: 0.6, weight: .bold)
                    .foregroundStyle(palette.clay)
            }

            HStack(spacing: 8) {
                GhostButton(title: "Confirm payment", action: confirm)
                Button(action: dismiss) {
                    Text("Not this")
                        .font(EvenFont.serif(15))
                        .foregroundStyle(palette.sub)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line, lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line, lineWidth: 1))
    }
}

private struct StatementTransactionRow: View {
    let transaction: BankTransaction
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.clay)
                .frame(width: 26, height: 26)
                .background(Circle().fill(palette.clay.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayName)
                    .font(EvenFont.serif(14))
                    .foregroundStyle(palette.ink)
                Text(date(transaction.bookingDate))
                    .capsLabel(8.5, tracking: 0.55)
                    .foregroundStyle(palette.sub)
            }
            Spacer()
            Text(currency(transaction.amount))
                .font(EvenFont.sans(12, .semibold))
                .foregroundStyle(palette.ink)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { palette.faint.frame(height: 1) }
    }
}

private func currency(_ cents: Int) -> String {
    currency(Decimal(cents) / 100)
}

private func currency(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "EUR"
    formatter.locale = Locale(identifier: "nl_NL")
    return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "€\(amount)"
}

private func date(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM"
    return formatter.string(from: value).uppercased()
}

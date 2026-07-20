import SwiftUI
import EvenCore

// Reusable task row and capture sheet used by the unified Todo workspace.

struct TodayView: View {
    @Bindable var model: AppModel
    var brandCollapsed: Binding<Bool>? = nil
    @Environment(\.palette) private var palette
    @State private var showQuickAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Today's large header IS the brand: glyph + wordmark at
                // rest, handing off to the bar's principal mark on scroll.
                HStack(spacing: 10) {
                    ScaleGlyph()
                        .stroke(palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 30, height: 30)
                    Text("Even")
                        .font(EvenFont.serif(34, .semibold, italic: true))
                        .foregroundStyle(palette.ink)
                    Spacer()
                }
                .padding(.top, 2)
                .background(
                    GeometryReader { headerGeo in
                        Color.clear.preference(
                            key: BrandHeaderVisibleKey.self,
                            value: headerGeo.frame(in: .named("todayScroll")).maxY > 8)
                    }
                )
                if model.partner == nil, let household = model.household {
                    InviteBanner(household: household)
                        .padding(.top, 6)
                }
                if let summary = model.summary {
                    BeamScaleView(model: model, summary: summary)
                        .frame(height: 240)
                        .padding(.top, 2)

                    Text(model.partner == nil
                         ? "All yours so far. Even starts mattering at two."
                         : summary.caption)
                        .font(EvenFont.serif(13.5, italic: true))
                        .foregroundStyle(palette.sub)
                        .padding(.top, 2)

                    sections(summary)

                    FooterAphorism(text: "Heavier work, heavier pebble. The beam does the arithmetic.")
                        .padding(.bottom, 26)
                } else if model.isLoading {
                    ProgressView().tint(palette.sub).padding(.top, 120)
                }
            }
            .padding(.horizontal, 20)
            .animation(.easeOut(duration: 0.25), value: model.summary?.week.id)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.summary?.sections)
        }
        .coordinateSpace(name: "todayScroll")
        .onPreferenceChange(BrandHeaderVisibleKey.self) { visible in
            brandCollapsed?.wrappedValue = !visible
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
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet(model: model)
        }
    }

    @ViewBuilder
    private func sections(_ summary: Summary) -> some View {
        let visible = summary.sections.filter { !$0.tasks.isEmpty }
        if visible.isEmpty {
            VStack(spacing: 10) {
                Text("Nothing on the pans yet.")
                    .font(EvenFont.serif(15))
                    .foregroundStyle(palette.ink)
                Text("Add the week's first piece of work — chores or the admin.")
                    .font(EvenFont.serif(13, italic: true))
                    .foregroundStyle(palette.sub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ForEach(visible, id: \.key) { section in
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.label.uppercased())
                        .capsLabel(9.5, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .padding(.top, 18)
                    ForEach(section.tasks) { task in
                        TaskRow(model: model, task: task)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}

/// 09 · "Your partner isn't in yet" card — the code stays on Today.
struct InviteBanner: View {
    let household: Household
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("YOUR PARTNER ISN'T IN YET")
                    .capsLabel(9, tracking: 1.6)
                    .foregroundStyle(palette.sub)
                Spacer()
                Circle().fill(palette.teal.opacity(0.5)).frame(width: 7, height: 7)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(household.inviteCode)
                    .font(EvenFont.serif(25, .medium))
                    .kerning(5.5)
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .accessibilityLabel("Invite code: \(household.inviteCode)")
                    .accessibilityIdentifier("invite-code-label")
                Spacer()
                ShareLink(item: "Join our household on Even — invite code \(household.inviteCode)") {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                        Text("Share")
                            .font(EvenFont.serif(14))
                    }
                    .foregroundStyle(palette.bg)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 9).fill(palette.ink))
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
            }
            .padding(.top, 8)

            Text("The code retires the moment they join.")
                .font(EvenFont.serif(12, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 7)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1))
    }
}

// MARK: - Task row

struct TaskRow: View {
    @Bindable var model: AppModel
    let task: HouseholdTask
    @Environment(\.palette) private var palette
    @State private var editing = false

    var body: some View {
        let owner = model.member(task.ownerMemberId)
        let ownerColor = owner.map { palette.member($0.color) } ?? palette.sub

        HStack(spacing: 10) {
            CheckCircle(done: task.done, color: ownerColor,
                        identifier: "check-\(task.title)") {
                Task { await model.toggle(task) }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(EvenFont.serif(15))
                    .strikethrough(task.done, color: palette.ink)
                    .foregroundStyle(palette.ink)
                HStack(spacing: 5) {
                    Text(task.googleEventUrl == nil ? "MANUAL" : "CALENDAR")
                        .capsLabel(8, tracking: 0.7, weight: .bold)
                        .foregroundStyle(task.googleEventUrl == nil ? palette.sub : palette.clay)
                    if !task.metaLine.isEmpty {
                        Text(task.metaLine.uppercased())
                            .capsLabel(8.5, tracking: 0.5)
                            .foregroundStyle(palette.sub)
                            .lineLimit(1)
                    }
                    if let state = task.calendarSyncState,
                       state != .synced && state != .notScheduled {
                        Text(state.label.uppercased())
                            .capsLabel(8, tracking: 0.45, weight: .bold)
                            .foregroundStyle(state == .retryRequired ? palette.clay : palette.ink)
                            .lineLimit(1)
                    }
                }
            }
            .opacity(task.done ? 0.42 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                OwnerChip(member: owner, palette: palette)
                Button { editing = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.sub)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.88))
                .accessibilityLabel("Edit \(task.title)")
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { palette.faint.frame(height: 1) }
        .animation(.easeOut(duration: 0.2), value: task.done)
        .contextMenu {
            Button {
                editing = true
            } label: {
                Label("Edit todo", systemImage: "pencil")
            }
            if let urlString = task.googleEventUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open calendar event", systemImage: "calendar")
                }
            }
            Button(role: .destructive) {
                Task {
                    await model.archive(task)
                }
            } label: {
                Label("Archive task", systemImage: "archivebox")
            }
        }
        .sheet(isPresented: $editing) {
            EditTaskSheet(model: model, task: task)
        }
    }
}

// MARK: - Create and edit

struct EditTaskSheet: View {
    @Bindable var model: AppModel
    let task: HouseholdTask
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var ownerId: UUID?
    @State private var recurrence: Recurrence = .none
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var saving = false
    @State private var confirmArchive = false

    var body: some View {
        SheetChrome(title: "EDIT TODO") {
            TodoEditorFields(title: $title, ownerId: $ownerId, recurrence: $recurrence,
                             hasDue: $hasDue, dueDate: $dueDate,
                             members: model.household?.members ?? [])

            if let state = task.calendarSyncState,
               state != .synced && state != .notScheduled {
                Label(state.label, systemImage: "exclamationmark.triangle")
                    .font(EvenFont.sans(11.5, .semibold))
                    .foregroundStyle(palette.clay)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(title: saving ? "Saving…" : "Save changes",
                          enabled: canSave && !saving) {
                guard let ownerId else { return }
                saving = true
                Task {
                    let ok = await model.updateTask(id: task.id, .init(
                        title: normalizedTitle,
                        section: task.section,
                        ownerMemberId: ownerId,
                        weight: task.weight,
                        recurrence: recurrence,
                        dueOn: hasDue ? TodoDate.dayString(dueDate) : nil,
                        clearDueOn: !hasDue))
                    saving = false
                    if ok { dismiss() }
                }
            }

            Button(role: .destructive) {
                confirmArchive = true
            } label: {
                Label("Archive todo", systemImage: "archivebox")
                    .font(EvenFont.sans(12, .semibold))
                    .foregroundStyle(palette.clay)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .disabled(saving)
        }
        .onAppear {
            title = task.title
            ownerId = task.ownerMemberId
            recurrence = task.recurrence
            hasDue = task.dueOn != nil
            if let dueOn = task.dueOn, let parsed = TodoDate.date(from: dueOn) {
                dueDate = parsed
            }
        }
        .confirmationDialog("Archive this todo?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive todo", role: .destructive) {
                Task {
                    await model.archive(task)
                    dismiss()
                }
            }
        } message: {
            Text("It will be removed from the household list and shared Calendar.")
        }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && ownerId != nil
    }
}

struct QuickAddSheet: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var ownerId: UUID?
    @State private var recurrence: Recurrence = .none
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var saving = false

    var body: some View {
        SheetChrome(title: "NEW TODO") {
            TodoEditorFields(title: $title, ownerId: $ownerId, recurrence: $recurrence,
                             hasDue: $hasDue, dueDate: $dueDate,
                             members: model.household?.members ?? [])

            PrimaryButton(title: saving ? "Adding…" : "Add todo",
                          enabled: !title.trimmingCharacters(in: .whitespaces).isEmpty
                                   && ownerId != nil && !saving) {
                guard let ownerId else { return }
                saving = true
                Task {
                    let ok = await model.createTask(.init(
                        title: title.trimmingCharacters(in: .whitespaces),
                        section: .chore,
                        ownerMemberId: ownerId,
                        weight: 1,
                        recurrence: recurrence,
                        dueOn: hasDue ? TodoDate.dayString(dueDate) : nil))
                    saving = false
                    if ok { dismiss() }
                }
            }
            .accessibilityIdentifier("task-save")
            .padding(.top, 4)
        }
        .onAppear { ownerId = model.me?.id }
    }
}

private struct TodoEditorFields: View {
    @Environment(\.palette) private var palette
    @Binding var title: String
    @Binding var ownerId: UUID?
    @Binding var recurrence: Recurrence
    @Binding var hasDue: Bool
    @Binding var dueDate: Date
    let members: [Member]

    var body: some View {
        UnderlineField(placeholder: "What needs doing?", text: $title, id: "task-title")

        optionRow("OWNER") {
            ForEach(members) { member in
                SelectPill(label: member.displayName.uppercased(),
                           selected: ownerId == member.id,
                           tint: palette.member(member.color)) {
                    ownerId = member.id
                }
            }
        }

        optionRow("REPEAT") {
            ForEach(Recurrence.allCases, id: \.self) { option in
                SelectPill(label: option.label.uppercased(), selected: recurrence == option) {
                    recurrence = option
                }
            }
        }

        HStack(spacing: 10) {
            SelectPill(label: hasDue ? "DUE \(EvenFormat.capsDate(TodoDate.dayString(dueDate)))" : "ADD A DUE DATE",
                       selected: hasDue) { hasDue.toggle() }
            if hasDue {
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(palette.clay)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func optionRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).capsLabel(9, tracking: 1.4).foregroundStyle(palette.sub)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }
}

private enum TodoDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayString(_ date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}

/// Bottom-sheet scaffold shared by Quick Add / propose / review sheets.
struct SheetChrome<Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Capsule().fill(palette.line)
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                HStack(alignment: .firstTextBaseline) {
                    Text(title).capsLabel(9.5, tracking: 1.5).foregroundStyle(palette.sub)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.sub)
                    }
                    .accessibilityIdentifier("sheet-close")
                }

                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .background(palette.card.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}


/// True while Today's in-content brand header is still on screen.
struct BrandHeaderVisibleKey: PreferenceKey {
    static var defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

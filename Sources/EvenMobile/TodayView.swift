import SwiftUI
import EvenCore

// Today — the balance scale over the week's completed work, then the task
// sections. Beam math per design: rot = clamp((50 − me%) · 0.5, ±8°).

struct TodayView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var showQuickAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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

    var body: some View {
        let owner = model.member(task.ownerMemberId)
        let ownerColor = owner.map { palette.member($0.color) } ?? palette.sub

        HStack(spacing: 10) {
            CheckCircle(done: task.done, color: ownerColor,
                        identifier: "check-\(task.title)") {
                Task { await model.toggle(task) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(EvenFont.serif(15))
                    .strikethrough(task.done, color: palette.ink)
                    .foregroundStyle(palette.ink)
                Text(task.metaLine.uppercased())
                    .capsLabel(8.5, tracking: 0.5)
                    .foregroundStyle(palette.sub)
            }
            .opacity(task.done ? 0.42 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)

            HeftDots(weight: task.weight, color: ownerColor)
            OwnerChip(member: owner, palette: palette)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { palette.faint.frame(height: 1) }
        .animation(.easeOut(duration: 0.2), value: task.done)
        .contextMenu {
            if let urlString = task.googleEventUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open calendar event", systemImage: "calendar")
                }
            }
            Button(role: .destructive) {
                Task {
                    try? await model.api.deleteTask(id: task.id)
                    await model.refreshAll()
                }
            } label: {
                Label("Archive task", systemImage: "archivebox")
            }
        }
    }
}

// MARK: - Beam scale

struct BeamScaleView: View {
    @Bindable var model: AppModel
    let summary: Summary
    @Environment(\.palette) private var palette

    private var rotation: Double {
        max(-8, min(8, Double(50 - summary.percentMe) * 0.5))
    }

    var body: some View {
        let meColor = model.me.map { palette.member($0.color) } ?? palette.clay
        let partnerColor = model.partner.map { palette.member($0.color) } ?? palette.teal

        GeometryReader { geo in
            let cx = geo.size.width / 2

            ZStack {
                // Pillar + base
                palette.ink.frame(width: 2, height: 132).position(x: cx, y: 64 + 66)
                Capsule().fill(palette.ink).frame(width: 120, height: 2).position(x: cx, y: 196)
                Text("WK \(summary.week.index)")
                    .capsLabel(7.5, tracking: 2.4)
                    .foregroundStyle(palette.sub)
                    .padding(.horizontal, 6)
                    .background(palette.bg)
                    .position(x: cx, y: 189)

                // Beam assembly (rotates as one)
                ZStack {
                    Capsule().fill(palette.ink).frame(width: 300, height: 3)
                    Circle().fill(palette.ink).frame(width: 8, height: 8)
                    Circle().fill(palette.ink).frame(width: 4, height: 4).offset(x: -148)
                    Circle().fill(palette.ink).frame(width: 4, height: 4).offset(x: 148)

                    PanView(pebbles: pebbles(for: model.me?.id), color: meColor,
                            name: model.me?.displayName ?? "You",
                            counterRotation: -rotation)
                        .offset(x: -148, y: 36)
                    PanView(pebbles: pebbles(for: model.partner?.id), color: partnerColor,
                            name: model.partner?.displayName ?? "— ?",
                            ghost: model.partner == nil,
                            counterRotation: -rotation)
                        .offset(x: 148, y: 36)

                    Text("\(summary.percentMe)")
                        .font(EvenFont.serif(34, .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: summary.percentMe)
                        .foregroundStyle(meColor)
                        .offset(x: -128, y: -26)
                    Text("\(summary.percentPartner)")
                        .font(EvenFont.serif(34, .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: summary.percentPartner)
                        .foregroundStyle(model.partner == nil ? AnyShapeStyle(palette.sub.opacity(0.6))
                                                              : AnyShapeStyle(partnerColor))
                        .offset(x: 128, y: -26)
                }
                .rotationEffect(.degrees(rotation))
                .animation(.spring(response: 1.1, dampingFraction: 0.55), value: rotation)
                .position(x: cx, y: 64)
            }
        }
    }

    private func pebbles(for memberId: UUID?) -> [Pebble] {
        guard let memberId else { return [] }
        return summary.pebbles.filter { $0.memberId == memberId }
    }
}

/// One hanging pan: strings, dish arc, pebble pile, name. Counter-rotated so
/// the pan stays level while the beam tilts.
struct PanView: View {
    @Environment(\.palette) private var palette
    let pebbles: [Pebble]
    let color: Color
    let name: String
    var ghost = false
    let counterRotation: Double

    var body: some View {
        ZStack {
            PanShape()
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round,
                                                        dash: ghost ? [3, 5] : []))
                .frame(width: 96, height: 58)
                .offset(y: 2)

            PebblePile(pebbles: pebbles, color: color)
                .frame(width: 78, height: 30)
                .offset(y: -12)

            Text(name.uppercased())
                .capsLabel(8.5, tracking: 1.7)
                .foregroundStyle(ghost ? AnyShapeStyle(palette.sub) : AnyShapeStyle(color))
                .offset(y: 24)
        }
        .frame(width: 96, height: 70)
        .opacity(ghost ? 0.45 : 1)
        .rotationEffect(.degrees(counterRotation), anchor: .top)
        .animation(.spring(response: 1.1, dampingFraction: 0.55), value: counterRotation)
    }
}

struct PanShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // strings — apex at the very top so the pan hangs off the beam end
        p.move(to: CGPoint(x: 0.5 * w, y: 0))
        p.addLine(to: CGPoint(x: 0.125 * w, y: 0.79 * h))
        p.move(to: CGPoint(x: 0.5 * w, y: 0))
        p.addLine(to: CGPoint(x: 0.875 * w, y: 0.79 * h))
        // dish
        p.move(to: CGPoint(x: 0.06 * w, y: 0.79 * h))
        p.addQuadCurve(to: CGPoint(x: 0.94 * w, y: 0.79 * h),
                       control: CGPoint(x: 0.5 * w, y: 1.14 * h))
        return p
    }
}

/// Pebbles settle from the dish upward, wrapping rows, newest on top.
struct PebblePile: View {
    let pebbles: [Pebble]
    let color: Color

    private func size(_ weight: Int) -> CGFloat {
        switch weight {
        case 1: return 8
        case 2: return 11
        default: return 14
        }
    }

    var body: some View {
        BottomWrapLayout(spacing: 1.5) {
            ForEach(Array(pebbles.enumerated()), id: \.offset) { index, pebble in
                Circle()
                    .fill(color)
                    .opacity(1 - min(0.35, Double(index) * 0.012))
                    .frame(width: size(pebble.weight), height: size(pebble.weight))
                    .transition(.asymmetric(
                        insertion: .offset(y: -52).combined(with: .scale(scale: 0.6)).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: pebbles.count)
    }
}

/// Wraps subviews into rows growing upward from the bottom, centered.
struct BottomWrapLayout: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(Int, CGSize)]] = [[]]
        var rowWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + spacing > bounds.width, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append((index, size))
            rowWidth += size.width + spacing
        }

        var y = bounds.maxY
        for row in rows {
            let rowHeight = row.map(\.1.height).max() ?? 0
            let totalWidth = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            var x = bounds.midX - totalWidth / 2
            for (index, size) in row {
                subviews[index].place(
                    at: CGPoint(x: x + size.width / 2, y: y - size.height / 2),
                    anchor: .center,
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y -= rowHeight + spacing
        }
    }
}

// MARK: - Quick add

struct QuickAddSheet: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var section: TaskSection = .chore
    @State private var ownerId: UUID?
    @State private var weight = 1
    @State private var recurrence: Recurrence = .none
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var saving = false

    var body: some View {
        SheetChrome(title: "NEW WORK — GOES ON THE SCALE") {
            UnderlineField(placeholder: "What needs doing?", text: $title, id: "task-title")

            optionRow("SECTION") {
                SelectPill(label: "CHORE", selected: section == .chore) { section = .chore }
                SelectPill(label: "THE ADMIN", selected: section == .admin) { section = .admin }
            }

            optionRow("OWNER") {
                ForEach(model.household?.members ?? []) { member in
                    SelectPill(label: member.displayName.uppercased(),
                               selected: ownerId == member.id,
                               tint: palette.member(member.color)) {
                        ownerId = member.id
                    }
                }
            }

            optionRow("HEFT") {
                ForEach(1...3, id: \.self) { w in
                    SelectPill(label: ["LIGHT", "SOLID", "HEAVY"][w - 1],
                               selected: weight == w) { weight = w }
                }
            }

            optionRow("REPEATS") {
                ForEach(Recurrence.allCases, id: \.self) { r in
                    SelectPill(label: r.label.uppercased(), selected: recurrence == r) { recurrence = r }
                }
            }

            HStack(spacing: 10) {
                SelectPill(label: hasDue ? "DUE \(EvenFormat.capsDate(dueString))" : "NO DUE DATE",
                           selected: hasDue) { hasDue.toggle() }
                if hasDue {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(palette.clay)
                }
                Spacer()
            }

            PrimaryButton(title: saving ? "Adding…" : "Add to the week",
                          enabled: !title.trimmingCharacters(in: .whitespaces).isEmpty
                                   && ownerId != nil && !saving) {
                guard let ownerId else { return }
                saving = true
                Task {
                    let ok = await model.createTask(.init(
                        title: title.trimmingCharacters(in: .whitespaces),
                        section: section,
                        ownerMemberId: ownerId,
                        weight: weight,
                        recurrence: recurrence,
                        dueOn: hasDue ? dueString : nil))
                    saving = false
                    if ok { dismiss() }
                }
            }
            .accessibilityIdentifier("task-save")
            .padding(.top, 4)
        }
        .onAppear { ownerId = model.me?.id }
    }

    private var dueString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: dueDate)
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

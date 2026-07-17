import SwiftUI
import EvenCore

// The Sunday ritual — intro, three steps, close the week, poured-out.

struct ResetView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var closing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.resetStep {
                case 0:
                    intro.transition(stepTransition)
                case 4:
                    pouredOut.transition(stepTransition)
                default:
                    stepHeader
                    Group {
                        switch model.resetStep {
                        case 1: weekHonestly
                        case 2: kindThing
                        default: trades
                        }
                    }
                    .id(model.resetStep)
                    .transition(stepTransition)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.resetStep)
        }
        .refreshable { await model.refreshReset() }
        .task { await model.refreshReset() }
    }

    /// Steps advance like pages: slide in from the trailing edge.
    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: Step 0 — intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SUNDAY RITUAL · 10 MINUTES")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 22)

            Text("The weekly\nreset")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 10)

            Text("Look at the pans honestly, say one kind thing each, trade what isn't working — then pour them out and start level.")
                .font(EvenFont.serif(15))
                .foregroundStyle(palette.ink)
                .lineSpacing(4)
                .padding(.top, 14)
                .frame(maxWidth: 300, alignment: .leading)

            Text("Together, on one screen. Phones down after.")
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            PrimaryButton(title: "Start the reset") {
                model.resetStep = 1
                Task { await model.refreshReset() }
            }
            .accessibilityIdentifier("reset-start")
            .padding(.top, 90)
        }
    }

    // MARK: Step chrome

    private var stepHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    model.resetStep = max(0, model.resetStep - 1)
                } label: {
                    Text("← BACK").capsLabel(10, tracking: 1.2).foregroundStyle(palette.sub)
                }
                Spacer()
                Text("RESET · \(model.resetStep) OF 3")
                    .capsLabel(10, tracking: 1.5)
                    .foregroundStyle(palette.sub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.faint)
                    Capsule().fill(palette.ink)
                        .frame(width: geo.size.width * CGFloat(model.resetStep) / 3)
                        .animation(.easeOut(duration: 0.3), value: model.resetStep)
                }
            }
            .frame(height: 3)
        }
        .padding(.top, 4)
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(EvenFont.serif(24, .medium))
                .foregroundStyle(palette.ink)
            Text(subtitle)
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.sub)
        }
        .padding(.top, 20)
    }

    // MARK: Step 1 — the week, honestly

    private var weekHonestly: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepTitle("The week, honestly.", "No blame in numbers. Just the picture.")

            if let reset = model.reset {
                VStack(spacing: 0) {
                    ForEach(reset.rows, id: \.key) { row in
                        SplitBarRow(model: model, row: row)
                    }
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text("THE BIGGEST CARRY").capsLabel(9, tracking: 1.5).foregroundStyle(palette.sub)
                    Text(reset.biggestCarry)
                        .font(EvenFont.serif(14, italic: true))
                        .foregroundStyle(palette.ink)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.faint))
                .padding(.top, 6)
            } else {
                ProgressView().tint(palette.sub).padding(.vertical, 60).frame(maxWidth: .infinity)
            }

            PrimaryButton(title: "Next — say one kind thing") { model.resetStep = 2 }
                .accessibilityIdentifier("reset-next-1")
                .padding(.top, 20)
        }
    }

    // MARK: Step 2 — say one kind thing

    private var kindThing: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepTitle("Say one kind thing.", "Out loud. The app can't do this part for you.")

            VStack(spacing: 12) {
                if let me = model.me {
                    AppreciationCard(model: model,
                                     from: me, to: model.partner,
                                     appreciation: appreciation(from: me.id),
                                     editable: true)
                }
                if let partner = model.partner {
                    AppreciationCard(model: model,
                                     from: partner, to: model.me,
                                     appreciation: appreciation(from: partner.id),
                                     editable: false)
                }
            }
            .padding(.top, 18)

            PrimaryButton(title: "Next — trade for next week") { model.resetStep = 3 }
                .accessibilityIdentifier("reset-next-2")
                .padding(.top, 20)
        }
    }

    private func appreciation(from memberId: UUID) -> Appreciation? {
        model.reset?.appreciations.first(where: { $0.fromMemberId == memberId })
    }

    // MARK: Step 3 — trades

    private var trades: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepTitle("Trade, don't tally.", "Swap the thinking, not just the doing.")

            VStack(spacing: 12) {
                ForEach(model.reset?.trades ?? []) { trade in
                    TradeRow(model: model, trade: trade)
                }
                TradeProposer(model: model)
            }
            .padding(.top, 18)

            PrimaryButton(title: closing ? "Pouring…" : "Close the week — pour the pans",
                          enabled: !closing) {
                closing = true
                Task {
                    if await model.closeWeek() {
                        model.resetStep = 4
                    }
                    closing = false
                }
            }
            .accessibilityIdentifier("reset-close")
            .padding(.top, 20)
        }
    }

    // MARK: Step 4 — poured out

    private var pouredOut: some View {
        VStack(spacing: 0) {
            ZStack {
                MiniScaleIllustration().scaleEffect(1.25)
                // spilled pebbles
                Circle().fill(palette.clay).opacity(0.4).frame(width: 6, height: 6).offset(x: -72, y: 26)
                Circle().fill(palette.clay).opacity(0.25).frame(width: 8, height: 8).offset(x: -54, y: 34)
                Circle().fill(palette.teal).opacity(0.35).frame(width: 7, height: 7).offset(x: 66, y: 28)
                Circle().fill(palette.teal).opacity(0.25).frame(width: 5, height: 5).offset(x: 46, y: 35)
            }
            .frame(height: 90)
            .padding(.top, 36)

            Text("Week \(model.lastClosedWeekIndex ?? max(1, (model.summary?.week.index ?? 2) - 1)), poured out.")
                .font(EvenFont.serif(27, .medium))
                .foregroundStyle(palette.ink)
                .padding(.top, 12)

            Text("Trades locked. The pans start empty on Monday — make it boring.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 10)

            Text("SEE YOU SUNDAY")
                .capsLabel(10, tracking: 2)
                .foregroundStyle(palette.sub)
                .padding(.top, 24)

            Button {
                model.resetStep = 0
            } label: {
                Text("BACK TO THE WEEK →")
                    .capsLabel(10, tracking: 1.2)
                    .foregroundStyle(palette.sub)
                    .underline()
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Split bar row

struct SplitBarRow: View {
    @Bindable var model: AppModel
    let row: ResetRow
    @Environment(\.palette) private var palette

    var body: some View {
        let meColor = model.me.map { palette.member($0.color) } ?? palette.clay
        let partnerColor = model.partner.map { palette.member($0.color) } ?? palette.teal

        VStack(spacing: 7) {
            HStack {
                Text(row.label)
                    .font(EvenFont.serif(15))
                    .foregroundStyle(palette.ink)
                Spacer()
                (Text("\(row.mePct)").foregroundStyle(meColor)
                 + Text(" · ").foregroundStyle(palette.sub)
                 + Text("\(row.partnerPct)").foregroundStyle(partnerColor))
                    .font(EvenFont.serif(15, .medium))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    meColor.frame(width: w * CGFloat(max(0, row.mePct - 7)) / 100)
                    LinearGradient(colors: [meColor, partnerColor], startPoint: .leading, endPoint: .trailing)
                    partnerColor.frame(width: w * CGFloat(max(0, row.partnerPct - 7)) / 100)
                }
                .clipShape(Capsule())
            }
            .frame(height: 5)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { palette.line.frame(height: 1) }
    }
}

// MARK: - Appreciation card

struct AppreciationCard: View {
    @Bindable var model: AppModel
    let from: Member
    let to: Member?
    let appreciation: Appreciation?
    let editable: Bool
    @Environment(\.palette) private var palette
    @State private var draftText = ""
    @State private var editing = false

    private var said: Bool { appreciation?.said ?? false }

    var body: some View {
        let color = palette.member(from.color)

        VStack(alignment: .leading, spacing: 6) {
            Text("\(from.displayName.uppercased()) → \(to?.displayName.uppercased() ?? "—")")
                .capsLabel(9, tracking: 1.8)
                .foregroundStyle(palette.sub)

            if editing {
                TextField("One thing you appreciated this week…", text: $draftText, axis: .vertical)
                    .font(EvenFont.serif(15.5, italic: true))
                    .foregroundStyle(palette.ink)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
            } else {
                Text(bodyText)
                    .font(EvenFont.serif(15.5, italic: true))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(3)
            }

            HStack {
                Text(footText)
                    .capsLabel(9, tracking: 1.3)
                    .foregroundStyle(said ? color : palette.sub)
                Spacer()
                if editable {
                    if editing {
                        Button {
                            editing = false
                            Task { await model.setAppreciation(body: draftText.isEmpty ? nil : draftText, said: true) }
                        } label: {
                            Text("SAID — SAVE").capsLabel(9, tracking: 1).foregroundStyle(color)
                        }
                    } else {
                        Button {
                            draftText = appreciation?.body ?? ""
                            editing = true
                        } label: {
                            Text(said ? "EDIT" : "TAP WHEN SAID").capsLabel(9, tracking: 1).foregroundStyle(palette.sub)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 16).fill(said ? color.opacity(0.14) : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(said ? color : palette.line,
                        style: StrokeStyle(lineWidth: 1.5, dash: said ? [] : [5, 4]))
        )
        .animation(.easeOut(duration: 0.2), value: said)
    }

    private var bodyText: String {
        if let body = appreciation?.body, !body.isEmpty { return "“\(body)”" }
        if said { return "Said, out loud." }
        return editable
            ? "Say one thing you appreciated this week. Out loud, to their face."
            : "In \(from.displayName)'s hands — their phone, their words."
    }

    private var footText: String {
        said ? "SAID — NICE." : (editable ? "" : "WAITING")
    }
}

// MARK: - Trade row + proposer

struct TradeRow: View {
    @Bindable var model: AppModel
    let trade: Trade
    @Environment(\.palette) private var palette

    var body: some View {
        let canAccept = trade.toMemberId == model.me?.id
        let fromName = model.member(trade.fromMemberId)?.displayName ?? "—"

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tradeText)
                    .font(EvenFont.serif(15))
                    .foregroundStyle(palette.ink)
                Text("FROM \(fromName.uppercased()) · \(trade.accepted ? "AGREED" : canAccept ? "TAP TO AGREE" : "WAITING FOR THEM")")
                    .capsLabel(8.5, tracking: 1.1)
                    .foregroundStyle(palette.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canAccept || trade.accepted {
                CheckCircle(done: trade.accepted, color: palette.ink, size: 28) {
                    guard canAccept else { return }
                    Task { await model.acceptTrade(trade, accepted: !trade.accepted) }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(trade.accepted ? palette.faint : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(trade.accepted ? palette.ink : palette.line, lineWidth: 1.5))
        .contextMenu {
            if trade.fromMemberId == model.me?.id {
                Button(role: .destructive) {
                    Task {
                        try? await model.api.deleteTrade(id: trade.id)
                        await model.refreshReset()
                    }
                } label: {
                    Label("Withdraw trade", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private var tradeText: String {
        let toName = model.member(trade.toMemberId)?.displayName ?? "—"
        return "\(toName) takes \(trade.taskTitle.lowercased().hasPrefix("the ") ? trade.taskTitle : trade.taskTitle)"
    }
}

/// Pick one of my open tasks to hand to the partner next week.
struct TradeProposer: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var picking = false

    private var myTasks: [HouseholdTask] {
        guard let summary = model.summary, let meId = model.me?.id else { return [] }
        let traded = Set(model.reset?.trades.map(\.taskId) ?? [])
        return summary.sections.flatMap(\.tasks)
            .filter { $0.ownerMemberId == meId && !traded.contains($0.id) }
    }

    var body: some View {
        if model.partner == nil {
            Text("Trades unlock once your partner joins.")
                .font(EvenFont.serif(12.5, italic: true))
                .foregroundStyle(palette.sub)
                .frame(maxWidth: .infinity)
        } else if picking {
            VStack(alignment: .leading, spacing: 6) {
                Text("HAND OVER — PICK ONE OF YOURS")
                    .capsLabel(9, tracking: 1.4)
                    .foregroundStyle(palette.sub)
                FlowRow(spacing: 6) {
                    ForEach(myTasks) { task in
                        SelectPill(label: task.title.uppercased(), selected: false) {
                            picking = false
                            Task { await model.proposeTrade(taskId: task.id) }
                        }
                    }
                }
                if myTasks.isEmpty {
                    Text("Nothing of yours left to trade this week.")
                        .font(EvenFont.serif(12.5, italic: true))
                        .foregroundStyle(palette.sub)
                }
                Button { picking = false } label: {
                    Text("CANCEL").capsLabel(9, tracking: 1).foregroundStyle(palette.sub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        } else {
            Button { picking = true } label: {
                Text("＋ PROPOSE A TRADE")
                    .capsLabel(10, tracking: 1.3)
                    .foregroundStyle(palette.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
        }
    }
}

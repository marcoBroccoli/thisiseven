import SwiftUI
import EvenCore

// Approval Inbox — drafts, not tasks. Partner-proposed in MVP (Gmail
// discovery is post-MVP); approving turns a draft into THE ADMIN work.

struct InboxView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var reviewing: Draft?
    /// Collapsed category keys — in-memory only, resets each launch.
    @State private var collapsed: Set<String> = []
    @State private var proposing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ScreenHeader(kicker: kicker,
                                 title: "Approval Inbox",
                                 subtitle: "Drafts, not tasks. Tap one to review.")
                    if model.googleStatus?.connected == true {
                        Button {
                            Task { await model.syncGmail() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.sub)
                                .rotationEffect(.degrees(model.gmailSyncing ? 360 : 0))
                                .animation(model.gmailSyncing
                                           ? .linear(duration: 1).repeatForever(autoreverses: false)
                                           : .default, value: model.gmailSyncing)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(palette.line, lineWidth: 1))
                        }
                        .accessibilityIdentifier("gmail-sync")
                        .disabled(model.gmailSyncing)
                    }
                }

                if model.googleStatus?.connected == false {
                    GoogleConnectCard(model: model)
                        .padding(.top, 14)
                }

                if model.gmailSyncing {
                    GmailReadingStrip(model: model)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if model.drafts.isEmpty && !model.gmailSyncing {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(DraftCategory.ordered, id: \.key) { cat in
                            let items = model.drafts.filter { $0.categoryKey == cat.key }
                            if !items.isEmpty {
                                DraftCategorySection(model: model, category: cat,
                                                     drafts: items,
                                                     collapsed: collapsedBinding(cat.key)) {
                                    reviewing = $0
                                }
                            }
                        }
                    }
                    .padding(.top, model.gmailSyncing ? 10 : 14)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.drafts)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: collapsed)

                    if !model.gmailSyncing, model.googleStatus?.hasMore == true {
                        ReadMoreMailButton(model: model)
                            .padding(.top, 12)
                    }

                    if !model.drafts.isEmpty {
                        FooterAphorism(text: "Nothing becomes shared work until one of you approves it.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
            .animation(.easeOut(duration: 0.3), value: model.gmailSyncing)
        }
        .refreshable { await model.refreshAll() }
        .overlay(alignment: .bottomTrailing) {
            Button {
                proposing = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.bg)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(palette.ink).shadow(color: .black.opacity(0.16), radius: 10, y: 5))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .accessibilityIdentifier("fab-propose")
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .sheet(item: $reviewing) { draft in
            DraftReviewSheet(model: model, draft: draft)
        }
        .sheet(isPresented: $proposing) {
            ProposeDraftSheet(model: model)
        }
    }

    private func collapsedBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { collapsed.contains(key) },
                set: { isOn in
                    if isOn { collapsed.insert(key) } else { collapsed.remove(key) }
                })
    }

    private var kicker: String {
        if let google = model.googleStatus, google.connected {
            let scanned = google.lastSyncCount.map { " · \($0) SCANNED" } ?? ""
            return "GMAIL DISCOVERY\(scanned) · \(model.drafts.count) PENDING"
        }
        return "SHARED APPROVALS · \(model.drafts.count) PENDING"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MiniScaleIllustration()
            Text("Inbox zero. Rare — enjoy it.")
                .font(EvenFont.serif(14.5, italic: true))
                .foregroundStyle(palette.sub)
            Text("Found a bill or an appointment? Propose it — your partner sees it here.")
                .font(EvenFont.serif(12.5, italic: true))
                .foregroundStyle(palette.sub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }
}

/// The tiny level scale used by empty states, per design.
struct MiniScaleIllustration: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Capsule().fill(palette.ink).frame(width: 150, height: 2)
            Circle().fill(palette.clay).frame(width: 8, height: 8).offset(x: -75, y: -1)
            Circle().fill(palette.teal).frame(width: 8, height: 8).offset(x: 75, y: -1)
            Triangle()
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 14, height: 10)
                .offset(y: 7)
        }
        .frame(width: 150, height: 36)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Card

struct DraftCard: View {
    @Bindable var model: AppModel
    let draft: Draft
    let open: () -> Void
    @Environment(\.palette) private var palette

    private var urgencyWord: String {
        ["LOW", "MEDIUM", "HIGH"][max(0, min(2, draft.urgency - 1))]
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(draft.fromLabel.uppercased())
                        .capsLabel(9.5, tracking: 0.8, weight: .bold)
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text(urgencyWord)
                        .capsLabel(8, tracking: 0.8, weight: .bold)
                        .foregroundStyle(draft.urgency == 3 ? palette.clay : palette.sub)
                }
                Text(draft.title.isEmpty ? draft.subject : draft.title)
                    .font(EvenFont.serif(14.5))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.leading)
                if let line = draft.summary ?? draft.sourcePreview, !line.isEmpty {
                    Text(line)
                        .font(EvenFont.serif(11.5, italic: true))
                        .foregroundStyle(palette.sub)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(summaryLine)
                    .capsLabel(9, tracking: 0.4)
                    .foregroundStyle(palette.sub)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityIdentifier("draft-card-\(draft.subject)")
    }

    private var summaryLine: String {
        var parts: [String] = draft.isFromGmail ? ["GMAIL"] : []
        if let owner = model.member(draft.ownerMemberId) {
            parts.append(owner.displayName.uppercased())
        }
        if let cents = draft.amountCents {
            parts.append(EvenFormat.euros(cents))
        }
        if let due = draft.dueOn {
            parts.append("DUE \(EvenFormat.capsDate(due))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Review sheet

struct DraftReviewSheet: View {
    @Bindable var model: AppModel
    let draft: Draft
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var ownerId: UUID?
    @State private var reminder: DraftReminder = .oneDay
    @State private var working = false

    var body: some View {
        SheetChrome(title: "REVIEW DRAFT — EVERYTHING EDITABLE") {
            UnderlineField(placeholder: "Task title", text: $title)

            HStack(spacing: 8) {
                Text("OWNER").capsLabel(9, tracking: 1.4).foregroundStyle(palette.sub)
                ForEach(model.household?.members ?? []) { member in
                    SelectPill(label: member.displayName.uppercased(),
                               selected: ownerId == member.id,
                               tint: palette.member(member.color)) {
                        ownerId = member.id
                    }
                }
                Spacer()
                Text(dueAmountLine)
                    .font(EvenFont.sans(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("CALENDAR REMINDER").capsLabel(9, tracking: 1.4).foregroundStyle(palette.sub)
                FlowRow(spacing: 6) {
                    ForEach(DraftReminder.allCases, id: \.self) { option in
                        SelectPill(label: option.label.uppercased(),
                                   selected: reminder == option) {
                            reminder = option
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                GhostButton(title: "Dismiss") {
                    working = true
                    Task {
                        await save()
                        await model.dismiss(draft)
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    working = true
                    Task {
                        await save()
                        await model.approve(draft)
                        dismiss()
                    }
                } label: {
                    Text("Approve → The Admin")
                        .font(EvenFont.serif(15, .medium))
                        .foregroundStyle(palette.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10).fill(palette.ink))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("draft-approve")
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            }
            .disabled(working)
            .padding(.top, 6)

            if draft.isFromGmail {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FROM THE MAIL PILE").capsLabel(9, tracking: 1.4).foregroundStyle(palette.sub)
                    Text(draft.subject)
                        .font(EvenFont.serif(12.5, italic: true))
                        .foregroundStyle(palette.sub)
                        .lineLimit(2)
                    if let preview = draft.sourcePreview, !preview.isEmpty {
                        Text(preview)
                            .font(EvenFont.serif(11.5, italic: true))
                            .foregroundStyle(palette.sub.opacity(0.8))
                            .lineLimit(3)
                    }
                    if let gmailID = draft.gmailMessageId {
                        OpenInGmailButton(messageID: gmailID)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.faint))
            }

            Text("Approval creates one piece of shared work with a reminder. Never before.")
                .font(EvenFont.serif(11.5, italic: true))
                .foregroundStyle(palette.sub)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            title = draft.title
            ownerId = draft.ownerMemberId
            reminder = draft.reminder
        }
    }

    private var dueAmountLine: String {
        var parts: [String] = []
        if let cents = draft.amountCents { parts.append(EvenFormat.euros(cents)) }
        if let due = draft.dueOn { parts.append("DUE \(EvenFormat.capsDate(due))") }
        return parts.joined(separator: " · ")
    }

    private func save() async {
        _ = await model.updateDraft(id: draft.id, .init(
            title: title.trimmingCharacters(in: .whitespaces),
            ownerMemberId: ownerId,
            reminder: reminder))
    }
}

// MARK: - Propose sheet

struct ProposeDraftSheet: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var fromLabel = ""
    @State private var subject = ""
    @State private var amount = ""
    @State private var urgency = 2
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var saving = false

    var body: some View {
        SheetChrome(title: "PROPOSE A DRAFT — PARTNER REVIEWS IT") {
            UnderlineField(placeholder: "From — e.g. Vattenfall, the dentist", text: $fromLabel, serifSize: 15, id: "draft-from")
            UnderlineField(placeholder: "What is it about?", text: $subject, id: "draft-subject")

            HStack(spacing: 6) {
                Text("URGENCY").capsLabel(9, tracking: 1.4).foregroundStyle(palette.sub)
                ForEach(1...3, id: \.self) { level in
                    SelectPill(label: ["LOW", "MEDIUM", "HIGH"][level - 1],
                               selected: urgency == level,
                               tint: level == 3 ? palette.clay : nil) {
                        urgency = level
                    }
                }
            }

            HStack(spacing: 10) {
                Text("€").font(EvenFont.serif(17)).foregroundStyle(palette.sub)
                UnderlineField(placeholder: "Amount (optional)", text: $amount, serifSize: 15)
                    .frame(width: 150)
                Spacer()
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

            PrimaryButton(title: saving ? "Proposing…" : "Send to the inbox",
                          enabled: !subject.trimmingCharacters(in: .whitespaces).isEmpty
                                   && !fromLabel.trimmingCharacters(in: .whitespaces).isEmpty
                                   && !saving) {
                saving = true
                Task {
                    let cents = Int((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                    let ok = await model.propose(.init(
                        fromLabel: fromLabel.trimmingCharacters(in: .whitespaces),
                        subject: subject.trimmingCharacters(in: .whitespaces),
                        urgency: urgency,
                        amountCents: cents > 0 ? cents : nil,
                        dueOn: hasDue ? dueString : nil))
                    saving = false
                    if ok { dismiss() }
                }
            }
            .accessibilityIdentifier("draft-save")
            .padding(.top, 4)
        }
    }

    private var dueString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: dueDate)
    }
}

// MARK: - Flow layout for reminder chips

struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}


// MARK: - Gmail reading strip (live sync)

/// Shown while the backend scans + classifies mail: three pebbles bounce in
/// sequence and the caption counts batches as drafts stream in below.
struct GmailReadingStrip: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var beat = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill([palette.clay, palette.teal, palette.sub][i])
                        .frame(width: 8, height: 8)
                        .offset(y: beat ? -5 : 2)
                        .animation(.easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18), value: beat)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Reading the mail pile…")
                    .font(EvenFont.serif(13.5, italic: true))
                    .foregroundStyle(palette.ink)
                Text(progressLine)
                    .capsLabel(8.5, tracking: 1.2)
                    .foregroundStyle(palette.sub)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 13).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .onAppear { beat = true }
        .animation(.easeOut(duration: 0.25), value: progressLine)
    }

    private var progressLine: String {
        let s = model.googleStatus
        let read = s?.classified ?? 0
        let total = s?.scanned ?? 0
        if total > 0 {
            return "\(read) OF \(total) READ · DRAFTS APPEAR AS THEY'RE FOUND"
        }
        return "DRAFTS APPEAR AS THEY'RE FOUND"
    }
}

/// Quiet dashed affordance: the last scan hit its batch limit — read on.
struct ReadMoreMailButton: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            Task { await model.syncGmail() }
        } label: {
            Text("READ MORE MAIL")
                .capsLabel(10, tracking: 1.3)
                .foregroundStyle(palette.sub)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityIdentifier("read-more-mail")
    }
}

// MARK: - Open in Gmail

/// Deep-links to the exact message in the Gmail app, falling back to the web
/// inbox when the app isn't installed. Open-with-fallback needs no
/// LSApplicationQueriesSchemes entry.
struct OpenInGmailButton: View {
    let messageID: String
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            open()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "envelope")
                    .font(.system(size: 10, weight: .medium))
                Text("OPEN IN GMAIL").capsLabel(9, tracking: 1.2)
            }
            .foregroundStyle(palette.clay)
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityIdentifier("open-in-gmail")
    }

    private func open() {
        let web = URL(string: "https://mail.google.com/mail/u/0/#all/\(messageID)")!
        #if canImport(UIKit) && !os(watchOS)
        if let app = URL(string: "googlegmail:///cv=\(messageID)") {
            UIApplication.shared.open(app, options: [:]) { success in
                if !success {
                    UIApplication.shared.open(web)
                }
            }
        } else {
            UIApplication.shared.open(web)
        }
        #endif
    }
}


// MARK: - Inbox categories

struct DraftCategory {
    let key: String
    let label: String

    /// Section order per Umur: money first, paperwork last.
    static let ordered: [DraftCategory] = [
        .init(key: "bills", label: "BILLS"),
        .init(key: "appointments", label: "APPOINTMENTS"),
        .init(key: "subscriptions", label: "SUBSCRIPTIONS"),
        .init(key: "admin", label: "THE ADMIN"),
        .init(key: "other", label: "EVERYTHING ELSE"),
    ]
}

/// One collapsible category of drafts: caps header with count + chevron,
/// cards fold away with a spring.
struct DraftCategorySection: View {
    @Bindable var model: AppModel
    let category: DraftCategory
    let drafts: [Draft]
    @Binding var collapsed: Bool
    let open: (Draft) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                collapsed.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("\(category.label) · \(drafts.count)")
                        .capsLabel(9.5, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.sub)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
            .accessibilityIdentifier("inbox-section-\(category.key)")

            if !collapsed {
                VStack(spacing: 10) {
                    ForEach(drafts) { draft in
                        DraftCard(model: model, draft: draft) { open(draft) }
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

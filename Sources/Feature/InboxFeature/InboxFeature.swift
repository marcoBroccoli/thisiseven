import AuthClient
import CalendarClient
import ComposableArchitecture
import Design
import DraftsClient
import EvenCore
import SwiftUI

@Reducer
public struct InboxFeature {
    @ObservableState
    public struct State: Equatable {
        public var drafts: IdentifiedArrayOf<Draft> = []
        public var isLoading = false
        public var error: String?
        public var surface: Surface = .inbox
        public var calendarItems: [CalendarItem] = []
        public var calendarMonthTitle = ""
        public var me: Member?
        public var partner: Member?
        public var showStamp = false
        @Presents public var review: Review.State?
        public init() {}

        public enum Surface: Equatable, Sendable {
            case inbox, calendar
        }
    }

    @Reducer
    public struct Review {
        @ObservableState
        public struct State: Equatable, Identifiable {
            public var id: UUID {
                draft.id
            }

            public var draft: Draft
            public var title: String
            public var ownerMemberId: UUID
            public var reminder: DraftReminder
            public var me: Member?
            public var partner: Member?

            public init(draft: Draft, me: Member?, partner: Member?) {
                self.draft = draft
                title = draft.title
                ownerMemberId = draft.ownerMemberId
                reminder = draft.reminder
                self.me = me
                self.partner = partner
            }
        }

        public enum Action: BindableAction {
            case binding(BindingAction<State>)
            case selectOwner(UUID)
            case selectReminder(DraftReminder)
            case approveTapped
            case dismissTapped
            case closeTapped
        }

        public var body: some ReducerOf<Self> {
            BindingReducer()
            Reduce { state, action in
                switch action {
                case let .selectOwner(id):
                    state.ownerMemberId = id
                    return .none
                case let .selectReminder(reminder):
                    state.reminder = reminder
                    return .none
                case .binding, .approveTapped, .dismissTapped, .closeTapped:
                    return .none
                }
            }
        }
    }

    public enum Action {
        case appear
        case membersLoaded(Member?, Member?)
        case draftsLoaded([Draft])
        case loadFailed(String)
        case selectDraft(UUID)
        case review(PresentationAction<Review.Action>)
        case approve(UUID)
        case dismiss(UUID)
        case approved(UUID)
        case dismissed(UUID)
        case actionFailed(String)
        case showStamp
        case hideStamp
        case selectSurface(State.Surface)
        case calendarLoaded(CalendarResponse)
        case calendarFailed(String)
        case delegate(Delegate)
        public enum Delegate: Equatable {
            case openToday
        }
    }

    @Dependency(\.draftsClient) var draftsClient
    @Dependency(\.calendarClient) var calendarClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appear:
                state.isLoading = true
                return .merge(
                    loadDrafts(),
                    .run { [authClient] send in
                        let members = await authClient.householdMembers()
                        await send(.membersLoaded(members.me, members.partner))
                    }
                )

            case let .membersLoaded(me, partner):
                state.me = me
                state.partner = partner
                return .none

            case let .draftsLoaded(drafts):
                state.isLoading = false
                state.drafts = IdentifiedArray(uniqueElements: drafts)
                return .none

            case let .loadFailed(message):
                state.isLoading = false
                state.error = message
                return .none

            case let .selectDraft(id):
                guard let draft = state.drafts[id: id] else { return .none }
                state.review = Review.State(draft: draft, me: state.me, partner: state.partner)
                return .none

            case .review(.presented(.closeTapped)):
                state.review = nil
                return .none

            case .review(.presented(.approveTapped)):
                guard let review = state.review else { return .none }
                let id = review.draft.id
                let body = EvenAPIClient.DraftPatchBody(
                    title: review.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerMemberId: review.ownerMemberId,
                    reminder: review.reminder
                )
                state.review = nil
                return .run { [draftsClient] send in
                    do {
                        _ = try await draftsClient.update(id, body)
                        _ = try await draftsClient.approve(id)
                        await send(.approved(id))
                    } catch {
                        await send(.actionFailed(String(describing: error)))
                    }
                }

            case .review(.presented(.dismissTapped)):
                guard let review = state.review else { return .none }
                let id = review.draft.id
                state.review = nil
                return .send(.dismiss(id))

            case .review:
                return .none

            case let .approve(id):
                return .run { [draftsClient] send in
                    do {
                        _ = try await draftsClient.approve(id)
                        await send(.approved(id))
                    } catch {
                        await send(.actionFailed(String(describing: error)))
                    }
                }

            case let .dismiss(id):
                return .run { [draftsClient] send in
                    do {
                        _ = try await draftsClient.dismiss(id)
                        await send(.dismissed(id))
                    } catch {
                        await send(.actionFailed(String(describing: error)))
                    }
                }

            case let .approved(id):
                state.drafts.remove(id: id)
                return .run { [clock] send in
                    await send(.showStamp)
                    try await clock.sleep(for: .seconds(1.6))
                    await send(.hideStamp)
                }

            case let .dismissed(id):
                state.drafts.remove(id: id)
                return .none

            case let .actionFailed(message):
                state.error = message
                return .none

            case .showStamp:
                state.showStamp = true
                return .none

            case .hideStamp:
                state.showStamp = false
                return .none

            case let .selectSurface(surface):
                state.surface = surface
                guard surface == .calendar else { return .none }
                return loadCalendar()

            case let .calendarLoaded(response):
                state.calendarItems = response.items
                state.calendarMonthTitle = monthTitle(from: response.from)
                return .none

            case let .calendarFailed(message):
                state.error = message
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$review, action: \.review) {
            Review()
        }
    }

    private func loadDrafts() -> Effect<Action> {
        .run { [draftsClient] send in
            do {
                try await send(.draftsLoaded(await draftsClient.pending()))
            } catch {
                await send(.loadFailed(String(describing: error)))
            }
        }
    }

    private func loadCalendar() -> Effect<Action> {
        .run { [calendarClient] send in
            let cal = Calendar.current
            let now = Date()
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            do {
                let response = try await calendarClient.window(f.string(from: start), f.string(from: end))
                await send(.calendarLoaded(response))
            } catch {
                await send(.calendarFailed(String(describing: error)))
            }
        }
    }

    private func monthTitle(from iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: iso) else { return iso }
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

public struct InboxFeatureView: View {
    @Bindable public var store: StoreOf<InboxFeature>

    public init(store: StoreOf<InboxFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                EvenTokens.paperRaised.ignoresSafeArea()
                Group {
                    switch store.surface {
                    case .inbox:
                        inboxSurface
                    case .calendar:
                        calendarSurface
                    }
                }

                if store.showStamp {
                    Text("APPROVED → TASK + CALENDAR EVENT")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(EvenTokens.paperRaised)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(EvenTokens.espresso, lineWidth: 2)
                                )
                        )
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                        .padding(.bottom, 60)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(item: $store.scope(state: \.review, action: \.review)) { reviewStore in
                DraftReviewSheet(store: reviewStore)
            }
        }
        .onAppear { store.send(.appear) }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.showStamp)
    }

    private var inboxSurface: some View {
        Group {
            if store.isLoading && store.drafts.isEmpty {
                ProgressView().tint(EvenTokens.espresso)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        chromeHeader(showCalendarChip: true)
                        Text("GMAIL DISCOVERY")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(EvenTokens.stone)
                            .padding(.top, 8)
                        Text("Approval Inbox")
                            .font(.system(size: 26, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                            .padding(.top, 4)
                        Text(store.drafts.isEmpty
                            ? "Inbox zero. Rare — enjoy it."
                            : "Drafts, not tasks. Tap one to review.")
                            .font(.system(size: 12.5, design: .serif))
                            .italic()
                            .foregroundStyle(EvenTokens.stone)
                            .padding(.top, 4)

                        if store.drafts.isEmpty {
                            emptyInbox
                                .padding(.top, 48)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.drafts) { draft in
                                    Button {
                                        store.send(.selectDraft(draft.id))
                                    } label: {
                                        draftCard(draft)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 14)

                            Text("Nothing reaches Calendar until you approve it.")
                                .font(.system(size: 12, design: .serif))
                                .italic()
                                .foregroundStyle(EvenTokens.stone)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var calendarSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chromeHeader(showCalendarChip: false)
                Text(store.calendarMonthTitle.isEmpty ? "Shared calendar" : store.calendarMonthTitle)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .italic()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                if store.calendarItems.isEmpty {
                    Text("No dated items this month yet.")
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    let grouped = Dictionary(grouping: store.calendarItems, by: \.dueOn)
                    ForEach(grouped.keys.sorted(), id: \.self) { day in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(dayLabel(day))
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(1.6)
                                .foregroundStyle(EvenTokens.stone)
                                .padding(.top, 18)
                                .padding(.bottom, 6)
                            ForEach(grouped[day] ?? []) { item in
                                calendarRow(item)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(EvenTokens.paperCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1)
                                )
                        )
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func chromeHeader(showCalendarChip: Bool) -> some View {
        HStack(spacing: 7) {
            EvenScaleGlyph()
                .stroke(EvenTokens.espresso, lineWidth: 1.6)
                .frame(width: 15, height: 15)
            Text("Even")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
            Spacer()
            if showCalendarChip {
                Button {
                    store.send(.selectSurface(.calendar))
                } label: {
                    Label("SHARED · GOOGLE", systemImage: "calendar")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(EvenTokens.stone)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    store.send(.selectSurface(.inbox))
                } label: {
                    Text("INBOX")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(EvenTokens.stone)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 56)
    }

    private var emptyInbox: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(EvenTokens.stone)
            Text("Nothing waiting.")
                .font(.system(size: 18, design: .serif))
                .italic()
        }
        .frame(maxWidth: .infinity)
    }

    private func draftCard(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(draft.fromLabel.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(EvenTokens.espresso)
                Spacer()
                Text(urgencyLabel(draft.urgency))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(urgencyColor(draft.urgency))
            }
            Text(draft.subject)
                .font(.system(size: 14.5, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            if let summary = draft.summary, !summary.isEmpty {
                Text(summary.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(EvenTokens.stone)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1.5)
        )
        .accessibilityIdentifier("draft-card-\(draft.subject)")
    }

    private func calendarRow(_ item: CalendarItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, design: .serif))
                Text(calendarMeta(item))
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(EvenTokens.stone)
            }
            Spacer()
            if let cents = item.amountCents {
                Text(euroString(cents))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            Text(ownerInitial(item.ownerMemberId))
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(EvenTokens.paperCard)
                .frame(width: 20, height: 20)
                .background(Circle().fill(ownerColor(item.ownerMemberId)))
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            EvenTokens.espresso.opacity(0.055).frame(height: 1)
        }
    }

    private func urgencyLabel(_ urgency: Int) -> String {
        switch urgency {
        case ...1: return "LOW"
        case 2: return "SOON"
        default: return "URGENT"
        }
    }

    private func urgencyColor(_ urgency: Int) -> Color {
        urgency >= 3 ? EvenTokens.terracotta : EvenTokens.stone
    }

    private func dayLabel(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: iso) else { return iso.uppercased() }
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date).uppercased()
    }

    private func calendarMeta(_ item: CalendarItem) -> String {
        var parts: [String] = []
        if let category = item.category { parts.append(category.uppercased()) }
        if item.googleEventUrl != nil { parts.append("GMAIL") }
        return parts.joined(separator: " · ")
    }

    private func euroString(_ cents: Int) -> String {
        let euros = Double(cents) / 100
        return euros.formatted(.currency(code: "EUR"))
    }

    private func ownerColor(_ id: UUID) -> Color {
        if id == store.me?.id { return EvenTokens.terracotta }
        if id == store.partner?.id { return EvenTokens.pine }
        return EvenTokens.stone
    }

    private func ownerInitial(_ id: UUID) -> String {
        if id == store.me?.id { return String(store.me?.displayName.prefix(1) ?? "A") }
        if id == store.partner?.id { return String(store.partner?.displayName.prefix(1) ?? "U") }
        return "?"
    }
}

private struct DraftReviewSheet: View {
    @Bindable var store: StoreOf<InboxFeature.Review>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(EvenTokens.espresso.opacity(0.14))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            HStack {
                Text("REVIEW DRAFT — EVERYTHING EDITABLE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                Spacer()
                Button("✕") { store.send(.closeTapped) }
                    .foregroundStyle(EvenTokens.stone)
            }
            .padding(.top, 12)

            TextField("Task title", text: $store.title)
                .font(.system(size: 17, design: .serif))
                .padding(.top, 10)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    EvenTokens.espresso.opacity(0.16).frame(height: 1.5)
                }

            HStack(spacing: 8) {
                Text("OWNER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                if let me = store.me {
                    ownerPill(me)
                }
                if let partner = store.partner {
                    ownerPill(partner)
                }
                Spacer()
                Text(dueAmountLine)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.top, 12)

            Text("CALENDAR REMINDER")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 12)
            FlowLayout(spacing: 6) {
                ForEach(DraftReminder.allCases, id: \.self) { option in
                    Button {
                        store.send(.selectReminder(option))
                    } label: {
                        Text(option.label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(store.reminder == option ? EvenTokens.espresso : EvenTokens.paperCard)
                            .foregroundStyle(store.reminder == option ? EvenTokens.paperCard : EvenTokens.espresso)
                            .overlay(
                                Capsule().stroke(
                                    EvenTokens.espresso.opacity(store.reminder == option ? 0 : 0.16),
                                    lineWidth: 1.5
                                )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 8) {
                Button {
                    store.send(.dismissTapped)
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(EvenTokens.stone)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    store.send(.approveTapped)
                } label: {
                    Text("Approve → Calendar")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.paperRaised)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10).fill(EvenTokens.espresso))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityIdentifier("draft-approve")
            }
            .padding(.top, 16)

            Text("Approval writes one event with a reminder. Never before.")
                .font(.system(size: 11.5, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.stone)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 20)
        .background(EvenTokens.paperCard.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func ownerPill(_ member: Member) -> some View {
        let selected = store.ownerMemberId == member.id
        return Button {
            store.send(.selectOwner(member.id))
        } label: {
            Text(member.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(selected ? EvenTokens.espresso : EvenTokens.paperCard)
                .foregroundStyle(selected ? EvenTokens.paperCard : EvenTokens.espresso)
                .overlay(
                    Capsule().stroke(EvenTokens.espresso.opacity(selected ? 0 : 0.16), lineWidth: 1.5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dueAmountLine: String {
        var parts: [String] = []
        if let cents = store.draft.amountCents {
            parts.append((Double(cents) / 100).formatted(.currency(code: "EUR")))
        }
        if let due = store.draft.dueOn {
            parts.append("DUE \(due)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Minimal wrapping layout for reminder chips (avoids pulling UIKit FlowLayout deps).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

#Preview("Inbox · populated") {
    InboxFeatureView(store: InboxPreviewSupport.populated())
}

#Preview("Inbox · empty") {
    InboxFeatureView(store: InboxPreviewSupport.empty())
}

#Preview("Inbox · calendar") {
    InboxFeatureView(store: InboxPreviewSupport.calendar())
}

#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI
    import UIKit
    import VisualEffects

    // MARK: - Chrome

    /// Pinned page chrome. The native segmented control is translucent, so the
    /// strip carries its own **opaque** paper band (plus a paper capsule under
    /// the control itself) — otherwise the list scrolls visibly through it.
    struct InboxSurfaceSwitcher: View {
        let surface: InboxReducer.State.Surface
        let onSelect: (InboxReducer.State.Surface) -> Void

        var body: some View {
            Picker("Surface", selection: selection) {
                Text("Inbox").tag(InboxReducer.State.Surface.inbox)
                Text("Shared · Google").tag(InboxReducer.State.Surface.calendar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(EvenTokens.paperCard)
            )
            .accessibilityIdentifier("inbox-surface-switch")
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background {
                // Paper + grain, matching the page ground — content must never
                // ghost through this strip while the list scrolls under it.
                EvenPaperBackground()
            }
            .overlay(alignment: .bottom) {
                EvenTokens.espresso.opacity(0.08).frame(height: 1)
            }
        }

        private var selection: Binding<InboxReducer.State.Surface> {
            Binding(get: { surface }, set: onSelect)
        }
    }

    // MARK: - Drafts surface

    /// A `List`, not a `ScrollView` — `swipeActions` is List-only, and the
    /// approve / dismiss swipes are the point of this surface.
    struct InboxDraftsSurface: View {
        let drafts: IdentifiedArrayOf<Draft>
        let isLoading: Bool
        let onSelectDraft: (UUID) -> Void
        let onApprove: (UUID) -> Void
        let onDismiss: (UUID) -> Void
        let onRefresh: () async -> Void

        private var showSkeleton: Bool {
            isLoading && drafts.isEmpty
        }

        var body: some View {
            List {
                InboxDraftsHeader(
                    isEmpty: !showSkeleton && drafts.isEmpty,
                    showsSwipeLegend: showSkeleton || !drafts.isEmpty
                )
                .inboxPaperListRow()
                .padding(.bottom, 14)

                if showSkeleton {
                    InboxDraftsSkeleton()
                        .inboxPaperListRow()
                } else if drafts.isEmpty {
                    InboxEmptyState()
                        .padding(.top, 48)
                        .inboxPaperListRow()
                } else {
                    ForEach(drafts) { draft in
                        InboxDraftRow(
                            draft: draft,
                            onSelect: { onSelectDraft(draft.id) },
                            onApprove: { onApprove(draft.id) },
                            onDismiss: { onDismiss(draft.id) }
                        )
                    }

                    Text("Nothing reaches Calendar until you approve it.")
                        .font(.system(size: 12, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                        .inboxPaperListRow()
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .evenScrollOnPaper()
            .refreshable { await onRefresh() }
            .animation(EvenMotion.reveal, value: showSkeleton)
        }
    }

    struct InboxDraftsSkeleton: View {
        var body: some View {
            VStack(spacing: 10) {
                ForEach(InboxSkeletonData.drafts) { draft in
                    InboxDraftCard(draft: draft)
                }
            }
            .loading(true)
            .accessibilityLabel("Loading inbox")
        }
    }

    struct InboxDraftsHeader: View {
        let isEmpty: Bool
        let showsSwipeLegend: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("GMAIL DISCOVERY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(EvenTokens.stone)
                Text("Approval Inbox")
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                    .padding(.top, 4)
                Text(isEmpty
                    ? "Inbox zero. Rare — enjoy it."
                    : "Tap a draft to fix the owner, title or date before it goes.")
                    .font(.system(size: 12.5, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.stone)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(EvenMotion.reveal, value: isEmpty)
                if showsSwipeLegend {
                    InboxSwipeLegend()
                        .padding(.top, 10)
                }
            }
        }
    }

    /// The two swipes, spelled out. Cheaper than a tutorial and it stays on
    /// screen — "as-is" is the whole distinction against tapping the row.
    struct InboxSwipeLegend: View {
        var body: some View {
            HStack(spacing: 14) {
                legend(
                    icon: "arrow.right",
                    text: "SWIPE · APPROVE AS-IS",
                    color: EvenTokens.pine
                )
                legend(
                    icon: "arrow.left",
                    text: "SWIPE · DISMISS",
                    color: EvenTokens.terracotta
                )
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Swipe a draft right to approve it as-is, left to dismiss it. Tap it to review first."
            )
        }

        private func legend(icon: String, text: String, color: Color) -> some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(text)
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.7)
            }
            .foregroundStyle(color)
        }
    }

    /// Row = card + gestures. A whole-row `Button` competes with the
    /// `swipeActions` recognizer (see `TodayTaskRow`), so tapping is a gesture.
    struct InboxDraftRow: View {
        let draft: Draft
        let onSelect: () -> Void
        let onApprove: () -> Void
        let onDismiss: () -> Void

        var body: some View {
            InboxDraftCard(draft: draft)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .gesture(
                    TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect()
                    }
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens review — owner, title and date — before approving.")
                .accessibilityActions {
                    Button("Approve as-is", action: onApprove)
                    Button("Dismiss", action: onDismiss)
                }
                .padding(.vertical, 5)
                // Text-only labels: iOS 26 stacks title over icon in the tray,
                // and the words are what make "as-is" legible in the first place.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Approve", action: onApprove)
                        .tint(EvenTokens.pine)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Dismiss", role: .destructive, action: onDismiss)
                        .tint(EvenTokens.terracotta)
                }
                .inboxPaperListRow()
        }
    }

    struct InboxDraftCard: View {
        let draft: Draft

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(draft.fromLabel.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(EvenTokens.espresso)
                    Spacer(minLength: 0)
                    Text(InboxCopy.urgencyLabel(draft.urgency))
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(InboxCopy.urgencyColor(draft.urgency))
                    // Reads as "this opens something" — the tap is review, not approve.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(EvenTokens.stone.opacity(0.6))
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
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(EvenTokens.paperCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1.5)
            )
            .accessibilityIdentifier("draft-card-\(draft.subject)")
        }
    }

    struct InboxEmptyState: View {
        var body: some View {
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
    }

    // MARK: - Calendar surface

    struct InboxCalendarSurface: View {
        let monthTitle: String
        /// `YYYY-MM-DD` first day of the loaded window — the grid's anchor month.
        let monthStart: String
        let items: [CalendarItem]
        let layout: InboxReducer.State.CalendarLayout
        let selectedDay: String?
        let me: Member?
        let partner: Member?
        let isLoading: Bool
        let onSelectLayout: (InboxReducer.State.CalendarLayout) -> Void
        let onStepMonth: (Int) -> Void
        let onSelectDay: (String?) -> Void
        let onRefresh: () async -> Void

        private var showSkeleton: Bool {
            isLoading && items.isEmpty
        }

        /// The grid filters the agenda below it; no selection means the month.
        private var visibleItems: [CalendarItem] {
            guard layout == .month, let selectedDay else { return items }
            return items.filter { $0.dueOn == selectedDay }
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    monthHeader
                    layoutPicker
                        .padding(.top, 14)

                    ZStack(alignment: .topLeading) {
                        if showSkeleton {
                            InboxCalendarSkeleton(me: me, partner: partner)
                                .transition(EvenMotion.fadeOnly)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                if layout == .month {
                                    InboxMonthGrid(
                                        monthStart: monthStart,
                                        items: items,
                                        selectedDay: selectedDay,
                                        me: me,
                                        partner: partner,
                                        onSelectDay: onSelectDay
                                    )
                                    .padding(.top, 16)
                                }
                                if items.isEmpty {
                                    emptyNote("No dated items this month yet.")
                                } else if visibleItems.isEmpty {
                                    emptyNote("Nothing on that day. Tap it again for the whole month.")
                                } else {
                                    calendarGroups
                                }
                            }
                            .transition(EvenMotion.fadeUp)
                        }
                    }
                    .animation(EvenMotion.reveal, value: showSkeleton)
                    .animation(EvenMotion.reveal, value: items.map(\.id))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .evenScrollOnPaper()
            .refreshable { await onRefresh() }
        }

        private var monthHeader: some View {
            HStack(spacing: 8) {
                monthStepButton(-1, icon: "chevron.left", label: "Previous month")
                Text(monthTitle.isEmpty ? "Shared calendar" : monthTitle)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                    .animation(EvenMotion.reveal, value: monthTitle)
                monthStepButton(1, icon: "chevron.right", label: "Next month")
            }
        }

        private func monthStepButton(_ step: Int, icon: String, label: String) -> some View {
            Button { onStepMonth(step) } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EvenTokens.espresso)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.evenPlain)
            .accessibilityLabel(label)
            .accessibilityIdentifier("calendar-month-\(step > 0 ? "next" : "previous")")
        }

        private var layoutPicker: some View {
            HStack(spacing: 8) {
                ForEach(InboxReducer.State.CalendarLayout.allCases, id: \.self) { option in
                    InboxSegmentChip(
                        title: option.label,
                        selected: layout == option
                    ) {
                        onSelectLayout(option)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Calendar layout")
            .accessibilityIdentifier("calendar-layout-switch")
        }

        private func emptyNote(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.stone)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        }

        private var calendarGroups: some View {
            let grouped = Dictionary(grouping: visibleItems, by: \.dueOn)
            return ForEach(grouped.keys.sorted(), id: \.self) { day in
                InboxCalendarDayGroup(
                    day: day,
                    items: grouped[day] ?? [],
                    me: me,
                    partner: partner
                )
                .padding(.top, 14)
            }
        }
    }

    /// Composer chip chrome (espresso fill / stroke) — same vocabulary as
    /// Today's organize chips, not a second segmented control.
    struct InboxSegmentChip: View {
        let title: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                    .background(selected ? EvenTokens.espresso : Color.clear)
                    .overlay(
                        Capsule().stroke(
                            EvenTokens.espresso.opacity(selected ? 0 : 0.16),
                            lineWidth: 1.5
                        )
                    )
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.evenPlain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    struct InboxCalendarSkeleton: View {
        let me: Member?
        let partner: Member?

        var body: some View {
            let grouped = Dictionary(grouping: InboxSkeletonData.calendarItems, by: \.dueOn)
            ForEach(grouped.keys.sorted(), id: \.self) { day in
                InboxCalendarDayGroup(
                    day: day,
                    items: grouped[day] ?? [],
                    me: me,
                    partner: partner
                )
                .padding(.top, 14)
            }
            .loading(true)
            .accessibilityLabel("Loading calendar")
        }
    }

    struct InboxCalendarDayGroup: View {
        let day: String
        let items: [CalendarItem]
        let me: Member?
        let partner: Member?

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(InboxCopy.dayLabel(day))
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                    .padding(.bottom, 2)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    InboxCalendarRow(
                        item: item,
                        drawsSeparator: index < items.count - 1,
                        me: me,
                        partner: partner
                    )
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
        }
    }

    struct InboxCalendarRow: View {
        let item: CalendarItem
        let drawsSeparator: Bool
        let me: Member?
        let partner: Member?

        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, design: .serif))
                    Text(InboxCopy.calendarMeta(item))
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(EvenTokens.stone)
                }
                Spacer()
                if let cents = item.amountCents {
                    Text(InboxCopy.euroString(cents))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                InboxOwnerBadge(
                    ownerMemberId: item.ownerMemberId,
                    me: me,
                    partner: partner
                )
            }
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                if drawsSeparator {
                    EvenTokens.espresso.opacity(0.055).frame(height: 1)
                }
            }
        }
    }

    struct InboxOwnerBadge: View {
        let ownerMemberId: UUID
        let me: Member?
        let partner: Member?

        var body: some View {
            if let member {
                EvenMemberAvatar(
                    memberId: member.id,
                    displayName: member.displayName,
                    accent: Color(hex: member.color.rgb),
                    hasAvatar: member.hasAvatar,
                    size: 20,
                    ringWidth: 1.25
                )
            } else {
                Text("?")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(EvenTokens.paperCard)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(EvenTokens.stone))
            }
        }

        private var member: Member? {
            if let me, ownerMemberId == me.id { return me }
            if let partner, ownerMemberId == partner.id { return partner }
            return nil
        }
    }

    // MARK: - List row chrome

    extension View {
        /// Page gutter as row insets (never `.padding` on the List — that
        /// narrows the scroll container and clips the swipe tray off the edge),
        /// clear background, no separators.
        func inboxPaperListRow() -> some View {
            listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Copy helpers

    enum InboxCopy {
        static func urgencyLabel(_ urgency: Int) -> String {
            switch urgency {
            case ...1: "LOW"
            case 2: "SOON"
            default: "URGENT"
            }
        }

        static func urgencyColor(_ urgency: Int) -> Color {
            urgency >= 3 ? EvenTokens.terracotta : EvenTokens.stone
        }

        static func dayLabel(_ iso: String) -> String {
            guard let date = InboxFormat.day.date(from: iso) else { return iso.uppercased() }
            return InboxFormat.weekdayMonthDay.string(from: date).uppercased()
        }

        static func calendarMeta(_ item: CalendarItem) -> String {
            var parts: [String] = []
            if let category = item.category { parts.append(category.uppercased()) }
            if item.googleEventUrl != nil { parts.append("GMAIL") }
            return parts.joined(separator: " · ")
        }

        static func euroString(_ cents: Int) -> String {
            (Double(cents) / 100).formatted(.currency(code: "EUR"))
        }
    }
#endif

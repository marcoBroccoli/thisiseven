#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI
    import VisualEffects

    // MARK: - Chrome

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
            .accessibilityIdentifier("inbox-surface-switch")
        }

        private var selection: Binding<InboxReducer.State.Surface> {
            Binding(get: { surface }, set: onSelect)
        }
    }

    // MARK: - Drafts surface

    struct InboxDraftsSurface: View {
        let drafts: IdentifiedArrayOf<Draft>
        let isLoading: Bool
        let onSelectDraft: (UUID) -> Void
        let onRefresh: () async -> Void

        private var showSkeleton: Bool {
            isLoading && drafts.isEmpty
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InboxDraftsHeader(isEmpty: !showSkeleton && drafts.isEmpty)

                    ZStack(alignment: .topLeading) {
                        if showSkeleton {
                            InboxDraftsSkeleton()
                                .padding(.top, 14)
                                .transition(EvenMotion.fadeOnly)
                        } else if drafts.isEmpty {
                            InboxEmptyState()
                                .padding(.top, 48)
                                .frame(maxWidth: .infinity)
                                .transition(EvenMotion.fadeUp)
                        } else {
                            InboxDraftList(
                                drafts: drafts,
                                onSelectDraft: onSelectDraft
                            )
                            .transition(EvenMotion.fadeUp)
                        }
                    }
                    .animation(EvenMotion.reveal, value: showSkeleton)
                    .animation(EvenMotion.reveal, value: drafts.ids)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .evenScrollOnPaper()
            .refreshable { await onRefresh() }
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
                    : "Drafts, not tasks. Tap one to review.")
                    .font(.system(size: 12.5, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.stone)
                    .padding(.top, 4)
                    .contentTransition(.opacity)
                    .animation(EvenMotion.reveal, value: isEmpty)
            }
        }
    }

    struct InboxDraftList: View {
        let drafts: IdentifiedArrayOf<Draft>
        let onSelectDraft: (UUID) -> Void

        var body: some View {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ForEach(drafts) { draft in
                        Button {
                            onSelectDraft(draft.id)
                        } label: {
                            InboxDraftCard(draft: draft)
                                // On the label — `.plain` only hits glyphs unless the
                                // full rounded rect is the content shape.
                                .contentShape(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .transition(Self.listTransition)
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

        /// Collapse upward on remove; settle in from below on insert.
        private static var listTransition: AnyTransition {
            .asymmetric(
                insertion: EvenMotion.fadeUp,
                removal: .opacity
                    .combined(with: .scale(scale: 0.96, anchor: .top))
                    .combined(with: .offset(y: -6))
            )
        }
    }

    struct InboxDraftCard: View {
        let draft: Draft

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(draft.fromLabel.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(EvenTokens.espresso)
                    Spacer()
                    Text(InboxCopy.urgencyLabel(draft.urgency))
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(InboxCopy.urgencyColor(draft.urgency))
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
        let items: [CalendarItem]
        let me: Member?
        let partner: Member?
        let isLoading: Bool
        let onRefresh: () async -> Void

        private var showSkeleton: Bool {
            isLoading && items.isEmpty
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(monthTitle.isEmpty ? "Shared calendar" : monthTitle)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .italic()
                        .frame(maxWidth: .infinity)

                    ZStack(alignment: .topLeading) {
                        if showSkeleton {
                            InboxCalendarSkeleton(me: me, partner: partner)
                                .transition(EvenMotion.fadeOnly)
                        } else if items.isEmpty {
                            Text("No dated items this month yet.")
                                .font(.system(size: 13, design: .serif))
                                .italic()
                                .foregroundStyle(EvenTokens.stone)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                                .transition(EvenMotion.fadeUp)
                        } else {
                            calendarGroups
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

        private var calendarGroups: some View {
            let grouped = Dictionary(grouping: items, by: \.dueOn)
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
                    .padding(.top, 18)
                    .padding(.bottom, 6)
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

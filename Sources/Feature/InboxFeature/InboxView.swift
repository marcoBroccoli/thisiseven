#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI
    import ToastUI

    @ViewAction(for: InboxReducer.self)
    public struct InboxView: View {
        @Bindable public var store: StoreOf<InboxReducer>

        public init(store: StoreOf<InboxReducer>) {
            self.store = store
        }

        public var body: some View {
            NavigationStack {
                Group {
                    switch store.surface {
                    case .inbox:
                        inboxSurface
                    case .calendar:
                        calendarSurface
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .evenPaperBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .tint(EvenTokens.espresso)
                // Surface switch is page chrome, not a nav action — and pinning it
                // here keeps the principal brand mark natively centred.
                .safeAreaInset(edge: .top, spacing: 0) {
                    surfaceSwitcher
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }
                .sheet(item: $store.scope(state: \.review, action: \.review)) { reviewStore in
                    ReviewView(store: reviewStore)
                }
            }
            .onAppear { send(.appear) }
            .toastHost(.even)
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                brandMark
            }
        }

        private var surfaceSwitcher: some View {
            Picker("Surface", selection: surfaceSelection) {
                Text("Inbox").tag(InboxReducer.State.Surface.inbox)
                Text("Shared · Google").tag(InboxReducer.State.Surface.calendar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("inbox-surface-switch")
        }

        private var surfaceSelection: Binding<InboxReducer.State.Surface> {
            Binding(
                get: { store.surface },
                set: { send(.selectSurface($0), animation: EvenMotion.page) }
            )
        }

        private var brandMark: some View {
            HStack(spacing: 7) {
                EvenScaleGlyph()
                    .stroke(
                        EvenTokens.espresso,
                        style: StrokeStyle(
                            lineWidth: EvenScaleGlyph.lineWidth(forSide: 15),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: 15, height: 15)
                Text("Even")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Even")
        }

        private var inboxSurface: some View {
            Group {
                if store.isLoading && store.drafts.isEmpty {
                    ProgressView().tint(EvenTokens.espresso)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("GMAIL DISCOVERY")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(EvenTokens.stone)
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
                                .contentTransition(.opacity)
                                .animation(EvenMotion.reveal, value: store.drafts.isEmpty)

                            ZStack(alignment: .topLeading) {
                                if store.drafts.isEmpty {
                                    emptyInbox
                                        .padding(.top, 48)
                                        .frame(maxWidth: .infinity)
                                        .transition(EvenMotion.fadeUp)
                                } else {
                                    VStack(spacing: 0) {
                                        VStack(spacing: 10) {
                                            ForEach(store.drafts) { draft in
                                                Button {
                                                    send(.selectDraft(draft.id))
                                                } label: {
                                                    draftCard(draft)
                                                }
                                                .buttonStyle(.plain)
                                                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                                .transition(draftListTransition)
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
                                    .transition(EvenMotion.fadeOnly)
                                }
                            }
                            .animation(EvenMotion.reveal, value: store.drafts.ids)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }

        /// Collapse upward on remove; settle in from below on insert.
        private var draftListTransition: AnyTransition {
            .asymmetric(
                insertion: EvenMotion.fadeUp,
                removal: .opacity
                    .combined(with: .scale(scale: 0.96, anchor: .top))
                    .combined(with: .offset(y: -6))
            )
        }

        private var calendarSurface: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.calendarMonthTitle.isEmpty ? "Shared calendar" : store.calendarMonthTitle)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .italic()
                        .frame(maxWidth: .infinity)

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
                                let dayItems = grouped[day] ?? []
                                ForEach(Array(dayItems.enumerated()), id: \.element.id) { index, item in
                                    calendarRow(item, drawsSeparator: index < dayItems.count - 1)
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
            .scrollContentBackground(.hidden)
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

        private func calendarRow(_ item: CalendarItem, drawsSeparator: Bool) -> some View {
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
                if drawsSeparator {
                    EvenTokens.espresso.opacity(0.055).frame(height: 1)
                }
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

    #Preview("Inbox · populated") {
        InboxView(store: InboxPreviewSupport.populated())
    }

    #Preview("Inbox · empty") {
        InboxView(store: InboxPreviewSupport.empty())
    }

    #Preview("Inbox · calendar") {
        InboxView(store: InboxPreviewSupport.calendar())
    }
#endif

#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SheetUI
    import SwiftUI

    @ViewAction(for: ReviewReducer.self)
    public struct ReviewView: View {
        @Bindable public var store: StoreOf<ReviewReducer>

        public init(store: StoreOf<ReviewReducer>) {
            self.store = store
        }

        public var body: some View {
            AutoSizingSheetView(surface: EvenTokens.paperRaised) {
                sheetContent
            } footer: {
                footer
            }
        }

        /// Elastic body — drives height; scrolls only once past the sheet ceiling
        /// (same FreeFlex pattern: `ScrollView` + `.scrollBounceBehavior(.basedOnSize)`).
        private var sheetContent: some View {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sourceBlock
                    titleField
                    metaLine
                    ownerSection
                    reminderSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Horizontal only — AutoSizingSheetView supplies the vertical inset.
                .padding(.horizontal, 24)
                .geometryGroup()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .toolbar { toolbarContent }
            .tint(EvenTokens.espresso)
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Review draft")
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text("Everything editable")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(EvenTokens.stone)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    send(.closeTapped)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EvenTokens.stone)
                }
                .accessibilityLabel("Close")
            }
        }

        // MARK: - Content

        private var sourceBlock: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.draft.fromLabel.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                if let summary = store.draft.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !store.draft.subject.isEmpty {
                    Text(store.draft.subject)
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        private var titleField: some View {
            TextField("Task title", text: $store.title, axis: .vertical)
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .lineLimit(1 ... 4)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    EvenTokens.espresso.opacity(0.14).frame(height: 1)
                }
        }

        @ViewBuilder
        private var metaLine: some View {
            if !amountLine.isEmpty {
                Text(amountLine)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(EvenTokens.espresso)
                    .padding(.top, 14)
            }
        }

        private var ownerSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Owner")
                HStack(spacing: 10) {
                    if let me = store.me {
                        ownerPill(me)
                    }
                    if let partner = store.partner {
                        ownerPill(partner)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 28)
        }

        /// Due date + reminder offset. The API carries no "detected" flag, so the
        /// provenance line is derived from what it *does* carry: a Gmail draft's
        /// `due_on` can only have come from the email extractor.
        private var reminderSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Calendar reminder")
                dueDateRow
                VStack(alignment: .leading, spacing: 10) {
                    Text(reminderCaption)
                        .font(.system(size: 12.5, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 8) {
                        ForEach(DraftReminder.allCases, id: \.self) { option in
                            reminderPill(option)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 28)
        }

        @ViewBuilder
        private var dueDateRow: some View {
            if let due = dueDate {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dueProvenance)
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(store.dueOnEdited ? EvenTokens.pine : EvenTokens.stone)
                        Text(InboxFormat.weekdayMonthDay.string(from: due))
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                    }
                    Spacer(minLength: 0)
                    DatePicker(
                        "Due date",
                        selection: dueBinding(fallback: due),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("draft-due-date")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(EvenTokens.paperCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(EvenTokens.espresso.opacity(0.12), lineWidth: 1)
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.draft.isFromGmail ? "NO DATE FOUND IN THE EMAIL" : "NO DATE ON THIS DRAFT")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(EvenTokens.stone)
                    Text("Nothing to count back from yet — add a date and the reminder has a day to work with.")
                        .font(.system(size: 12.5, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                        .fixedSize(horizontal: false, vertical: true)
                    chip("ADD A DATE", selected: false) {
                        send(.setDueDate(Date()))
                    }
                    .accessibilityIdentifier("draft-add-due-date")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(EvenTokens.paperCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(EvenTokens.espresso.opacity(0.12), lineWidth: 1)
                        )
                )
            }
        }

        private var dueDate: Date? {
            store.dueOn.flatMap { InboxFormat.day.date(from: $0) }
        }

        private func dueBinding(fallback: Date) -> Binding<Date> {
            Binding(
                get: { dueDate ?? fallback },
                set: { send(.setDueDate($0)) }
            )
        }

        private var dueProvenance: String {
            if store.dueOnEdited { return "YOU CHANGED THIS" }
            if store.dueOnWasDetected { return "DETECTED FROM THE EMAIL" }
            return "ON THIS DRAFT"
        }

        private var reminderCaption: String {
            store.dueOn == nil
                ? "Pick how early Calendar should nudge you — it needs a date above to count back from."
                : "Tap the date to change it. Calendar nudges you this far ahead of it."
        }

        private func sectionLabel(_ text: String) -> some View {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
        }

        // MARK: - Footer (rigid — no vertical padding; sheet supplies it)

        private var footer: some View {
            VStack(spacing: 12) {
                EvenPrimaryButton(
                    "Approve → Calendar",
                    enabled: !store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    accessibilityId: "draft-approve"
                ) {
                    send(.approveTapped)
                }

                Button {
                    send(.dismissTapped)
                } label: {
                    Text("Dismiss draft")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(EvenTokens.stone)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.evenPlain)
            }
            .padding(.horizontal, 24)
        }

        // MARK: - Chips

        private func ownerPill(_ member: Member) -> some View {
            chip(
                member.displayName.uppercased(),
                selected: store.ownerMemberId == member.id
            ) {
                send(.selectOwner(member.id))
            }
        }

        private func reminderPill(_ option: DraftReminder) -> some View {
            chip(option.label.uppercased(), selected: store.reminder == option) {
                send(.selectReminder(option))
            }
        }

        private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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
        }

        /// Amount only — the date moved into the reminder section, where it is
        /// formatted, sourced and editable instead of a raw ISO string.
        private var amountLine: String {
            guard let cents = store.draft.amountCents else { return "" }
            return (Double(cents) / 100).formatted(.currency(code: "EUR"))
        }
    }

    /// Minimal wrapping layout for reminder chips (avoids pulling UIKit FlowLayout deps).
    struct FlowLayout: Layout {
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

    #if DEBUG
        #Preview("Review draft · no date detected") {
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    ReviewView(
                        store: Store(
                            initialState: ReviewReducer.State(
                                draft: {
                                    var draft = PreviewData.pendingDrafts[1]
                                    draft.dueOn = nil
                                    return draft
                                }(),
                                me: PreviewData.ada,
                                partner: PreviewData.umut
                            )
                        ) {
                            ReviewReducer()
                        }
                    )
                }
        }

        #Preview("Review draft") {
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    ReviewView(
                        store: Store(
                            initialState: ReviewReducer.State(
                                draft: PreviewData.pendingDrafts[0],
                                me: PreviewData.ada,
                                partner: PreviewData.umut
                            )
                        ) {
                            ReviewReducer()
                        }
                    )
                }
        }
    #endif
#endif

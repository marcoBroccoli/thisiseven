#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SheetUI
    import SwiftUI

    @ViewAction(for: ComposerReducer.self)
    public struct ComposerView: View {
        @Bindable public var store: StoreOf<ComposerReducer>
        let me: Member?
        let partner: Member?

        public init(store: StoreOf<ComposerReducer>, me: Member?, partner: Member?) {
            self.store = store
            self.me = me
            self.partner = partner
        }

        public var body: some View {
            AutoSizingSheetView(surface: EvenTokens.paperRaised) {
                sheetContent
            } footer: {
                footer
            }
        }

        /// Form body — plain `VStack`, not a `ScrollView`.
        ///
        /// The `if` insert is animated on `send` so the stack pushes. The sheet
        /// detent uses the same curve (`AutoSizingSheet.contentAnimation`) with
        /// quantized `presentationDetents` writes so the two stay in step without
        /// the old per-frame UIKit thrash. Reintroduce scrolling only if a device
        /// actually needs it for this form.
        private var sheetContent: some View {
            VStack(alignment: .leading, spacing: 0) {
                TextField("What needs doing?", text: $store.title)
                    .font(.system(size: 18, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                    .padding(.bottom, 10)
                    .overlay(alignment: .bottom) {
                        EvenTokens.espresso.opacity(0.16).frame(height: 1.5)
                    }
                    .accessibilityIdentifier("task-title")

                ComposerSectionLabel(text: "Owner")
                HStack(spacing: 8) {
                    ComposerOwnerChip(
                        label: me?.displayName ?? "Me",
                        accent: Color(hex: (me?.color ?? .clay).rgb),
                        selected: store.ownerIsMe
                    ) {
                        send(.selectOwner(true))
                    }
                    if partner != nil {
                        ComposerOwnerChip(
                            label: partner?.displayName ?? "Partner",
                            accent: Color(hex: (partner?.color ?? .teal).rgb),
                            selected: !store.ownerIsMe
                        ) {
                            send(.selectOwner(false))
                        }
                    }
                }
                .padding(.top, 4)

                ComposerSectionLabel(text: "Heft — how much this weighs")
                HStack(spacing: 8) {
                    ForEach(1 ... 3, id: \.self) { w in
                        ComposerHeftChip(
                            weight: w,
                            selected: store.weight == w
                        ) {
                            send(.selectWeight(w))
                        }
                    }
                }
                .padding(.top, 4)

                ComposerSectionLabel(text: "Due")
                FlowWrap(spacing: 8) {
                    ForEach(ComposerReducer.DueOption.allCases, id: \.self) { option in
                        ComposerChoiceChip(
                            title: option.label,
                            // An imported civil day that isn't a chip keeps
                            // `dueOnOverride` — no preset should look selected.
                            selected: store.dueOnOverride == nil && store.dueOption == option
                        ) {
                            send(.selectDue(option))
                        }
                    }
                }
                .padding(.top, 4)

                ComposerSectionLabel(text: "Section")
                HStack(spacing: 8) {
                    ComposerChoiceChip(
                        title: "Chore",
                        selected: store.section == .chore
                    ) {
                        send(.selectSection(.chore))
                    }
                    ComposerChoiceChip(
                        title: "Admin",
                        selected: store.section == .admin
                    ) {
                        send(.selectSection(.admin))
                    }
                }
                .padding(.top, 4)

                ComposerSectionLabel(text: "Repeat")
                FlowWrap(spacing: 8) {
                    ForEach(Recurrence.allCases, id: \.self) { recurrence in
                        ComposerChoiceChip(
                            title: recurrence.label,
                            selected: store.recurrence == recurrence
                        ) {
                            // Animation on the send — not `.animation(value:)` —
                            // so the TCA write and the `if` insert share one
                            // transaction and the VStack actually pushes.
                            send(
                                .selectRecurrence(recurrence),
                                animation: AutoSizingSheet.contentAnimation
                            )
                        }
                    }
                }
                .padding(.top, 4)

                if store.showsRepeatEnd {
                    ComposerRepeatEndSection(
                        option: store.endOption,
                        date: $store.endDate,
                        count: $store.endCount,
                        dateRange: store.endDateRange
                    ) {
                        send(.selectEnd($0), animation: AutoSizingSheet.contentAnimation)
                    }
                }

                // TODO: Calendar reminder toggle — tasks API has no reminder field
                // (drafts only; see DraftReminder / PATCH drafts). Hide until wired.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Horizontal only — AutoSizingSheetView supplies the vertical inset.
            .padding(.horizontal, 24)
            // Sheet content is already geometry-grouped by AutoSizingSheetView —
            // a second group here forces an extra layout pass per frame of the
            // insert spring and reads as lag.
            .toolbar { toolbarContent }
            .tint(EvenTokens.espresso)
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                Text(store.isEditing ? "Edit todo" : "New todo")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    send(.cancelTapped)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EvenTokens.stone)
                }
                .accessibilityLabel("Close")
            }
        }

        // MARK: - Footer (rigid — no vertical padding; sheet supplies it)

        private var footer: some View {
            EvenPrimaryButton(
                store.isEditing ? "Save changes" : "Add to Today",
                enabled: !store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityId: "task-save"
            ) {
                send(.saveTapped)
            }
            .padding(.horizontal, 24)
        }
    }

    #if DEBUG
        #Preview("Composer") {
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    ComposerView(
                        store: TodayPreviewSupport.composer(),
                        me: PreviewData.ada,
                        partner: PreviewData.umut
                    )
                }
        }

        #Preview("Composer · bounded repeat") {
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    ComposerView(
                        store: TodayPreviewSupport.composerBoundedRepeat(),
                        me: PreviewData.ada,
                        partner: PreviewData.umut
                    )
                }
        }

        #Preview("Composer · edit") {
            Color.clear
                .sheet(isPresented: .constant(true)) {
                    ComposerView(
                        store: TodayPreviewSupport.composerEditing(),
                        me: PreviewData.ada,
                        partner: PreviewData.umut
                    )
                }
        }
    #endif
#endif

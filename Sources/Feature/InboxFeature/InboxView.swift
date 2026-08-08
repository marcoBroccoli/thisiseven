#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

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
                        InboxDraftsSurface(
                            drafts: store.drafts,
                            isLoading: store.isLoading,
                            onSelectDraft: { send(.selectDraft($0)) },
                            onApprove: { send(.approveDraft($0), animation: EvenMotion.reveal) },
                            onDismiss: { send(.dismissDraft($0), animation: EvenMotion.reveal) },
                            onRefresh: { await send(.refresh).finish() }
                        )
                    case .calendar:
                        InboxCalendarSurface(
                            monthTitle: store.calendarMonthTitle,
                            monthStart: store.calendarFrom,
                            items: store.calendarItems,
                            layout: store.calendarLayout,
                            selectedDay: store.selectedCalendarDay,
                            me: store.me,
                            partner: store.partner,
                            isLoading: store.isCalendarLoading,
                            onSelectLayout: { send(.selectCalendarLayout($0), animation: EvenMotion.reveal) },
                            onStepMonth: { send(.stepCalendarMonth($0)) },
                            onSelectDay: { send(.selectCalendarDay($0), animation: EvenMotion.reveal) },
                            onRefresh: { await send(.refresh).finish() }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        EvenBrandMark()
                    }
                }
                .evenPaperNavigationChrome()
                // Surface switch is page chrome, not a nav action — and pinning it
                // here keeps the principal brand mark natively centred.
                .safeAreaInset(edge: .top, spacing: 0) {
                    InboxSurfaceSwitcher(
                        surface: store.surface,
                        onSelect: { send(.selectSurface($0), animation: EvenMotion.page) }
                    )
                }
                .sheet(item: $store.scope(state: \.review, action: \.review)) { reviewStore in
                    ReviewView(store: reviewStore)
                }
            }
            .onAppear { send(.appear) }
            .evenToastHost()
        }
    }

    #Preview("Inbox · populated") {
        InboxView(store: InboxPreviewSupport.populated())
    }

    #Preview("Inbox · empty") {
        InboxView(store: InboxPreviewSupport.empty())
    }

    #Preview("Inbox · loading") {
        InboxView(store: InboxPreviewSupport.loading())
    }

    #Preview("Inbox · calendar") {
        InboxView(store: InboxPreviewSupport.calendar())
    }

    #Preview("Inbox · calendar loading") {
        InboxView(store: InboxPreviewSupport.calendarLoading())
    }
#endif

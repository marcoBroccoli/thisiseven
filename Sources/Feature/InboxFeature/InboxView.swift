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
                        // No mailbox, no drafts surface — the invitation
                        // replaces the list rather than sitting under it.
                        if store.showsConnectGoogle {
                            InboxConnectGoogleSurface(
                                onConnect: { send(.connectGoogleTapped) },
                                onRefresh: { await send(.refresh).finish() }
                            )
                            .transition(EvenMotion.fadeOnly)
                        } else {
                            InboxDraftsSurface(
                                drafts: store.drafts,
                                isLoading: store.isLoading,
                                isSyncing: store.isSyncing,
                                onSelectDraft: { send(.selectDraft($0)) },
                                onApprove: { send(.approveDraft($0), animation: EvenMotion.reveal) },
                                onDismiss: { send(.dismissDraft($0), animation: EvenMotion.reveal) },
                                onFetch: { send(.fetchTapped, animation: EvenMotion.reveal) },
                                onRefresh: { await send(.refresh).finish() }
                            )
                            .transition(EvenMotion.fadeOnly)
                        }
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
                .padding(.top, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(EvenMotion.reveal, value: store.showsConnectGoogle)
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

    #Preview("Inbox · fetching") {
        InboxView(store: InboxPreviewSupport.fetching())
    }

    #Preview("Inbox · not connected") {
        InboxView(store: InboxPreviewSupport.notConnected())
    }

    #Preview("Inbox · calendar") {
        InboxView(store: InboxPreviewSupport.calendar())
    }

    #Preview("Inbox · calendar loading") {
        InboxView(store: InboxPreviewSupport.calendarLoading())
    }
#endif

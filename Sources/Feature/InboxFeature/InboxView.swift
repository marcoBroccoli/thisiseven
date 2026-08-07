#if os(iOS)
    import ComposableArchitecture
    import Design
    import IGTabBar
    import SwiftUI

    @ViewAction(for: InboxReducer.self)
    public struct InboxView: View {
        @Bindable public var store: StoreOf<InboxReducer>
        private var tabBarProgress: Binding<CGFloat>?

        public init(
            store: StoreOf<InboxReducer>,
            tabBarProgress: Binding<CGFloat>? = nil
        ) {
            self.store = store
            self.tabBarProgress = tabBarProgress
        }

        public var body: some View {
            NavigationStack {
                Group {
                    switch store.surface {
                    case .inbox:
                        InboxDraftsSurface(
                            drafts: store.drafts,
                            isLoading: store.isLoading,
                            tabBarProgress: tabBarProgress,
                            onSelectDraft: { send(.selectDraft($0)) },
                            onRefresh: { await send(.refresh).finish() }
                        )
                    case .calendar:
                        InboxCalendarSurface(
                            monthTitle: store.calendarMonthTitle,
                            items: store.calendarItems,
                            me: store.me,
                            partner: store.partner,
                            isLoading: store.isCalendarLoading,
                            tabBarProgress: tabBarProgress,
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
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

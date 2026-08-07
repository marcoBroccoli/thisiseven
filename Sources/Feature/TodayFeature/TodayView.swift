#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import IGTabBar
    import SwiftUI

    @ViewAction(for: TodayReducer.self)
    public struct TodayView: View {
        @Bindable public var store: StoreOf<TodayReducer>
        private var tabBarProgress: Binding<CGFloat>?

        public init(
            store: StoreOf<TodayReducer>,
            tabBarProgress: Binding<CGFloat>? = nil
        ) {
            self.store = store
            self.tabBarProgress = tabBarProgress
        }

        public var body: some View {
            NavigationStack {
                TodayContentSurface(
                    summary: store.summary,
                    me: store.me,
                    partner: store.partner,
                    isLoading: store.isLoading,
                    organizeMode: store.organizeMode,
                    tabBarProgress: tabBarProgress,
                    onToggle: { send(.toggle($0)) },
                    onEdit: { send(.edit($0)) },
                    onDelete: { send(.delete($0)) },
                    onOrganize: { send(.organize($0), animation: EvenMotion.indicator) },
                    onRefresh: { await send(.refresh).finish() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        EvenBrandMark()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            send(.addTapped)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityIdentifier("fab-add-task")
                        .accessibilityLabel("Add task")
                    }
                }
                .evenPaperNavigationChrome()
                .sheet(item: $store.scope(state: \.composer, action: \.composer)) { composerStore in
                    ComposerView(store: composerStore, me: store.me, partner: store.partner)
                }
            }
            .onAppear { send(.appear) }
            .evenToastHost()
        }
    }

    #Preview("Today · populated") {
        TodayView(store: TodayPreviewSupport.populated())
    }

    #Preview("Today · empty") {
        TodayView(store: TodayPreviewSupport.empty())
    }

    #Preview("Today · loading") {
        TodayView(store: TodayPreviewSupport.loading())
    }

    #Preview("Today · toggle fails") {
        let store = TodayPreviewSupport.toggleFails()
        return TodayView(store: store)
            .task {
                try? await Task.sleep(for: TodayPreviewSupport.defaultFailureLag)
                store.send(.view(.toggle(PreviewData.laundry.id)))
            }
    }

    #Preview("Today · create fails") {
        let store = TodayPreviewSupport.createFails()
        return TodayView(store: store)
            .task {
                try? await Task.sleep(for: TodayPreviewSupport.defaultFailureLag)
                store.send(.createTask)
            }
    }

    #Preview("Today · create succeeds") {
        let store = TodayPreviewSupport.createSucceeds()
        return TodayView(store: store)
            .task {
                try? await Task.sleep(for: TodayPreviewSupport.defaultFailureLag)
                store.send(.createTask)
            }
    }
#endif

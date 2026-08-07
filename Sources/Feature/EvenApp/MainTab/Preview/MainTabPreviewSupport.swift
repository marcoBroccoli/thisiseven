#if os(iOS)
    import ComposableArchitecture
    import EvenCore
    import HouseholdClient
    import HouseholdRealtimeClient
    import InboxFeature
    import ProfileFeature
    import ToastClient
    import TodayFeature

    enum MainTabPreviewSupport {
        @MainActor
        static func populated() -> StoreOf<MainTabReducer> {
            var state = MainTabReducer.State()
            state.today = {
                var today = TodayReducer.State()
                today.summary = PreviewData.summary
                today.me = PreviewData.ada
                today.partner = PreviewData.umut
                today.isLoading = false
                return today
            }()
            state.inbox = {
                var inbox = InboxReducer.State()
                inbox.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
                inbox.hasLoadedDrafts = true
                inbox.me = PreviewData.ada
                inbox.partner = PreviewData.umut
                inbox.isLoading = false
                return inbox
            }()
            state.profile = {
                var profile = ProfileReducer.State()
                profile.isLoading = false
                profile.me = PreviewData.ada
                profile.partner = PreviewData.umut
                profile.householdName = PreviewData.household.name
                profile.inviteCode = PreviewData.household.inviteCode
                profile.draftDisplayName = PreviewData.ada.displayName
                return profile
            }()

            return Store(initialState: state) {
                MainTabReducer()
            } withDependencies: {
                $0.householdClient = .previewValue
                $0.householdRealtimeClient = .previewValue
                $0.toastClient = .silent()
            }
        }
    }
#endif

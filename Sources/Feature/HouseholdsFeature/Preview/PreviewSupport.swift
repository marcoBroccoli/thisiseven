#if os(iOS)
    import ComposableArchitecture
    import EvenCore
    import HouseholdClient
    import ToastClient

    enum HouseholdsPreviewSupport {
        /// Two places, one seat still open with an address on it, and an invite
        /// waiting from a third.
        @MainActor
        static func populated() -> StoreOf<HouseholdsReducer> {
            store(state: loadedState())
        }

        /// A seat held for someone — the row opened on its invite controls.
        @MainActor
        static func pendingInvite() -> StoreOf<HouseholdsReducer> {
            var state = loadedState()
            state.expandedHouseholdID = PreviewData.seaHouseRow.id
            return store(state: state)
        }

        /// Giving up a seat — the confirmation, with what it costs spelled out.
        @MainActor
        static func leaveConfirmation() -> StoreOf<HouseholdsReducer> {
            var state = loadedState()
            state.expandedHouseholdID = PreviewData.atticRow.id
            state.leavingHousehold = PreviewData.atticRow
            return store(state: state)
        }

        /// Nowhere yet — only the invite addressed to you.
        @MainActor
        static func invitesOnly() -> StoreOf<HouseholdsReducer> {
            var state = HouseholdsReducer.State()
            state.isLoading = false
            state.invites = [PreviewData.inviteForMe]
            state.myDisplayName = PreviewData.ada.displayName
            return store(
                state: state,
                list: { HouseholdsResponse(households: [], invites: [PreviewData.inviteForMe]) }
            )
        }

        @MainActor
        static func creating() -> StoreOf<HouseholdsReducer> {
            var state = loadedState()
            state.path = .create
            state.newHouseholdName = "The Cabin"
            state.newDisplayName = PreviewData.ada.displayName
            return store(state: state)
        }

        @MainActor
        static func accepting() -> StoreOf<HouseholdsReducer> {
            var state = loadedState()
            state.path = .accept
            state.acceptingInvite = PreviewData.inviteForMe
            state.acceptDisplayName = PreviewData.ada.displayName
            return store(state: state)
        }

        /// First frame — the skeleton, held on screen.
        @MainActor
        static func loading() -> StoreOf<HouseholdsReducer> {
            store(
                state: HouseholdsReducer.State(),
                list: PreviewDelay.delayed(.seconds(60)) { PreviewData.households }
            )
        }

        @MainActor
        private static func loadedState() -> HouseholdsReducer.State {
            var state = HouseholdsReducer.State()
            state.isLoading = false
            state.households = IdentifiedArray(uniqueElements: PreviewData.householdRows)
            state.invites = [PreviewData.inviteForMe]
            state.myDisplayName = PreviewData.ada.displayName
            state.activeHouseholdID = PreviewData.householdId
            return state
        }

        @MainActor
        private static func store(
            state: HouseholdsReducer.State,
            list: (@Sendable () async throws -> HouseholdsResponse)? = nil
        ) -> StoreOf<HouseholdsReducer> {
            Store(initialState: state) {
                HouseholdsReducer()
            } withDependencies: {
                $0.householdClient = .previewValue
                if let list {
                    $0.householdClient.list = list
                }
                $0.toastClient = .silent()
            }
        }
    }
#endif

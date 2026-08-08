import ComposableArchitecture
import EvenCore

public enum HouseholdSetupPreviewSupport {
    /// Interactive whole-flow store: choice → create/join → invite / waiting.
    public static func flow() -> StoreOf<HouseholdSetupReducer> {
        Store(initialState: HouseholdSetupReducer.State()) {
            HouseholdSetupReducer()
        }
    }

    public static func choice() -> StoreOf<HouseholdSetupReducer> {
        Store(initialState: HouseholdSetupReducer.State()) {
            HouseholdSetupReducer()
        }
    }

    public static func create() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.path = .create
        state.name = PreviewData.household.name
        state.displayName = PreviewData.ada.displayName
        return Store(initialState: state) {
            HouseholdSetupReducer()
        }
    }

    public static func inviteReveal() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.path = .inviteReveal
        state.inviteReveal = PreviewData.household.inviteCode
        return Store(initialState: state) {
            HouseholdSetupReducer()
        }
    }

    public static func join() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.path = .join
        return Store(initialState: state) {
            HouseholdSetupReducer()
        }
    }

    /// The newcomer's case: a seat is already being held for this address.
    public static func choiceWithInvite() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.invites = [PreviewData.inviteForMe]
        return Store(initialState: state) {
            HouseholdSetupReducer()
        }
    }

    public static func acceptInvite() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.path = .acceptInvite
        state.invites = [PreviewData.inviteForMe]
        state.acceptingInvite = PreviewData.inviteForMe
        state.displayName = PreviewData.ada.displayName
        return Store(initialState: state) {
            HouseholdSetupReducer()
        }
    }

    public static func waiting() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.path = .waiting
        state.inviteReveal = PreviewData.household.inviteCode
        return Store(initialState: state) {
            HouseholdSetupReducer()
        }
    }
}

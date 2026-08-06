import ComposableArchitecture
import EvenCore
import HouseholdClient

public enum HouseholdSetupPreviewSupport {
    /// Interactive whole-flow store: choice → create/join → invite / waiting.
    public static func flow() -> StoreOf<HouseholdSetupReducer> {
        Store(initialState: HouseholdSetupReducer.State()) {
            HouseholdSetupReducer()
        } withDependencies: { deps in
            mockHousehold(&deps)
        }
    }

    public static func choice() -> StoreOf<HouseholdSetupReducer> {
        Store(initialState: HouseholdSetupReducer.State()) {
            HouseholdSetupReducer()
        } withDependencies: { deps in
            mockHousehold(&deps)
        }
    }

    public static func create() -> StoreOf<HouseholdSetupReducer> {
        var state = HouseholdSetupReducer.State()
        state.path = .create
        state.name = PreviewData.household.name
        state.displayName = PreviewData.ada.displayName
        return Store(initialState: state) {
            HouseholdSetupReducer()
        } withDependencies: { deps in
            mockHousehold(&deps)
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
        } withDependencies: { deps in
            mockHousehold(&deps)
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

    private static func mockHousehold(_ deps: inout DependencyValues) {
        deps.householdClient.create = { _, _ in PreviewData.household }
        deps.householdClient.join = { _, _ in PreviewData.household }
    }
}

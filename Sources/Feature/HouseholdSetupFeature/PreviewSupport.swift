import ComposableArchitecture
import EvenCore
import HouseholdClient

public enum HouseholdSetupPreviewSupport {
    public static func choice() -> StoreOf<HouseholdSetupFeature> {
        Store(initialState: HouseholdSetupFeature.State()) {
            HouseholdSetupFeature()
        } withDependencies: {
            $0.householdClient.create = { _, _ in PreviewData.household }
            $0.householdClient.join = { _, _ in PreviewData.household }
        }
    }

    public static func create() -> StoreOf<HouseholdSetupFeature> {
        var state = HouseholdSetupFeature.State()
        state.path = .create
        state.name = PreviewData.household.name
        state.displayName = PreviewData.ada.displayName
        return Store(initialState: state) {
            HouseholdSetupFeature()
        } withDependencies: {
            $0.householdClient.create = { _, _ in PreviewData.household }
        }
    }

    public static func inviteReveal() -> StoreOf<HouseholdSetupFeature> {
        var state = HouseholdSetupFeature.State()
        state.path = .inviteReveal
        state.inviteReveal = PreviewData.household.inviteCode
        return Store(initialState: state) {
            HouseholdSetupFeature()
        }
    }

    public static func join() -> StoreOf<HouseholdSetupFeature> {
        var state = HouseholdSetupFeature.State()
        state.path = .join
        return Store(initialState: state) {
            HouseholdSetupFeature()
        } withDependencies: {
            $0.householdClient.join = { _, _ in PreviewData.household }
        }
    }
}

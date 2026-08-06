import ComposableArchitecture

public enum LoginPreviewSupport {
    public static func flow() -> StoreOf<LoginReducer> {
        Store(initialState: LoginReducer.State()) {
            LoginReducer()
        }
    }

    public static func error() -> StoreOf<LoginReducer> {
        var state = LoginReducer.State()
        state.error = "Apple Sign In returned no identity token."
        return Store(initialState: state) {
            LoginReducer()
        }
    }
}

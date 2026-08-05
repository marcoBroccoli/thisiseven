import AuthClient
import ComposableArchitecture
import EvenCore

public enum LoginPreviewSupport {
    public static func flow() -> StoreOf<LoginReducer> {
        Store(initialState: LoginReducer.State()) {
            LoginReducer()
        } withDependencies: {
            mockAuth(&$0)
        }
    }

    public static func error() -> StoreOf<LoginReducer> {
        var state = LoginReducer.State()
        state.error = "Apple Sign In returned no identity token."
        return Store(initialState: state) {
            LoginReducer()
        } withDependencies: {
            mockAuth(&$0)
        }
    }

    private static func mockAuth(_ deps: inout DependencyValues) {
        deps.authClient.signInWithApple = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
        deps.authClient.signInEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
        deps.authClient.signUpEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
    }
}

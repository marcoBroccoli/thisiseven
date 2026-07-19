#if os(iOS)
import GoogleSignIn
import SwiftUI

@main
struct HouseholdCommandCenterMobileApp: App {
    @StateObject private var store = DemoHouseholdStore()

    var body: some Scene {
        WindowGroup {
            HouseholdRootView(store: store)
                .task {
                    await store.restoreGoogleSession()
                }
                .onOpenURL { url in
                    GoogleMobileOAuthCoordinator.handle(url)
                }
        }
    }
}
#endif

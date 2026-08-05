import ComposableArchitecture
import ConnectionsFeature
import Design
import EvenCore
import HouseholdSetupFeature
import InboxFeature
import OnboardingFeature
import SwiftUI
import TodayFeature

/// TCA composition root — boot → onboarding stack → Today + Inbox.
public struct EvenAppRootView: View {
    @State private var store: StoreOf<AppReducer>

    public init(store: StoreOf<AppReducer> = Store(initialState: .booting) { AppReducer() }) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        Group {
            switch store.state {
            case .booting:
                BootSplashView()
            case .onboarding:
                if let store = store.scope(state: \.onboarding, action: \.onboarding) {
                    OnboardingFeatureView(store: store)
                }
            case .householdSetup:
                if let store = store.scope(state: \.householdSetup, action: \.householdSetup) {
                    HouseholdSetupFeatureView(store: store)
                }
            case .connections:
                if let store = store.scope(state: \.connections, action: \.connections) {
                    ConnectionsFeatureView(store: store)
                }
            case .ready:
                if let store = store.scope(state: \.ready, action: \.ready) {
                    MainTabView(store: store)
                }
            }
        }
        .task {
            if EvenLaunchArguments.resetSession {
                await SharedSession.store.signOut()
            }
            await store.send(.appStarted).finish()
        }
    }
}

private struct MainTabView: View {
    @Bindable var store: StoreOf<MainReducer>

    var body: some View {
        TabView(selection: $store.tab.sending(\.selectTab)) {
            TodayFeatureView(store: store.scope(state: \.today, action: \.today))
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(MainReducer.State.Tab.today)

            InboxFeatureView(store: store.scope(state: \.inbox, action: \.inbox))
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(MainReducer.State.Tab.inbox)
        }
        .tint(EvenTokens.espresso)
    }
}

private struct BootSplashView: View {
    @State private var glyphProgress: CGFloat = 0
    @State private var showWordmark = false

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .trim(from: 0, to: glyphProgress)
                .stroke(EvenTokens.espresso, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 52, height: 4)
                .rotationEffect(.degrees(-8))
            Text("Even")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
                .opacity(showWordmark ? 1 : 0)
                .offset(y: showWordmark ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EvenTokens.paperRaised.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65)) { glyphProgress = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45)) {
                showWordmark = true
            }
        }
    }
}

#Preview("App · booting") {
    EvenAppRootView(store: EvenAppPreviewSupport.booting())
}

#Preview("App · onboarding") {
    EvenAppRootView(store: EvenAppPreviewSupport.onboarding())
}

#Preview("App · ready") {
    EvenAppRootView(store: EvenAppPreviewSupport.ready())
}

import ComposableArchitecture
import Design
import EvenCore
import SwiftUI

@ViewAction(for: ConnectionsReducer.self)
public struct ConnectionsView: View {
    @Bindable public var store: StoreOf<ConnectionsReducer>

    public init(store: StoreOf<ConnectionsReducer>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .evenPaperBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .animation(EvenMotion.reveal, value: store.showsBack)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .tint(EvenTokens.espresso)
        }
        .onAppear { send(.appear) }
        // Feature-owned toast chrome; reducer still uses `toastClient.show`.
        .evenToastHost()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if store.showsBack {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    send(.backTapped, animation: EvenMotion.page)
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("connections-back")
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -8)),
                        removal: .opacity.combined(with: .offset(x: -8))
                    )
                )
            }
        }
        ToolbarItem(placement: .principal) {
            Text("Email & Calendar")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
        }
    }

    private var pageContent: some View {
        ZStack(alignment: .topLeading) {
            pathContent
                .id(store.path)
                .transition(EvenMotion.fadeUp)
        }
        .padding(.horizontal, ConnectionsSetupChrome.horizontalInset)
        .padding(.top, ConnectionsSetupChrome.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Path motion stays on the body — never on the footer, or the CTA
        // cross-fades with the page instead of morphing in place.
        .animation(EvenMotion.page, value: store.path)
        .animation(EvenMotion.reveal, value: store.working)
        .animation(EvenMotion.reveal, value: store.isCheckingStatus)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConnectionsPathFooter(store: store)
                .padding(.horizontal, ConnectionsSetupChrome.horizontalInset)
                .padding(.bottom, ConnectionsSetupChrome.bottomInset)
        }
    }

    @ViewBuilder
    private var pathContent: some View {
        switch store.path {
        case .why:
            ConnectionsWhyView()
        case .scopes:
            ConnectionsScopesView(store: store)
        case .connected:
            ConnectionsConnectedView()
        }
    }
}

#Preview("Connections · flow") {
    ConnectionsView(store: ConnectionsPreviewSupport.flow())
}

#Preview("Connections · flow · connect fails") {
    ConnectionsView(store: ConnectionsPreviewSupport.flowConnectFails())
}

#Preview("Connections · flow · status fails") {
    ConnectionsView(store: ConnectionsPreviewSupport.flowStatusFails())
}

#Preview("Connections · flow · already connected") {
    ConnectionsView(store: ConnectionsPreviewSupport.flowAlreadyConnected())
}

#Preview("Connections · why") {
    ConnectionsView(store: ConnectionsPreviewSupport.why())
}

#Preview("Connections · scopes") {
    ConnectionsView(store: ConnectionsPreviewSupport.scopes())
}

#Preview("Connections · connected") {
    ConnectionsView(store: ConnectionsPreviewSupport.connected())
}

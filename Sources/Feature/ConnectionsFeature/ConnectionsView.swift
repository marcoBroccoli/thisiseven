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
        EvenScreenChrome(eyebrow: "Email & Calendar", title: "Connect Gmail\n& Calendar.") {
            Text("Bills become drafts in a shared Approval Inbox. Your partner approves before anything becomes a task.")
                .font(.system(size: 15.5))
                .foregroundStyle(Color(hex: 0x6E6353))
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(store.statusLine)
                    .font(.system(size: 18, design: .serif))
                if let email = store.email {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(EvenTokens.stone)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EvenTokens.paperCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 28)

            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(EvenTokens.terracotta)
                    .padding(.top, 12)
            }

            Spacer()

            EvenPrimaryButton(store.working ? "Connecting…" : "Connect Google", enabled: !store.working) {
                send(.connectTapped)
            }
            Button("Skip for now") { send(.skipTapped) }
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(EvenTokens.stone)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .onAppear { send(.appear) }
    }
}

#Preview("Connections · flow") {
    ConnectionsView(store: ConnectionsPreviewSupport.flow())
}

#Preview("Connections · disconnected") {
    ConnectionsView(store: ConnectionsPreviewSupport.disconnected())
}

#Preview("Connections · connected") {
    ConnectionsView(store: ConnectionsPreviewSupport.connected())
}

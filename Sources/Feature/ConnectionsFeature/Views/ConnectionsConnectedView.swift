import ComposableArchitecture
import Design
import SwiftUI

struct ConnectionsConnectedView: View {
    var body: some View {
        ConnectionsSetupChrome.stepScreen {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    ConnectionsDrawnCheckmark()

                    Text("Gmail & Calendar\nconnected.")
                        .font(.system(size: 26, weight: .medium, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(EvenTokens.espresso)
                        .padding(.top, 20)

                    ConnectionsSetupChrome.italicNote(
                        "A shared “Even” calendar now publishes to Google — subscribe from either of your phones.",
                        size: 14.5
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
                    .padding(.top, 12)

                    ConnectionsCalendarCallout()
                        .padding(.top, 22)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview("Connections · connected") {
    ConnectionsView(store: ConnectionsPreviewSupport.connected())
}

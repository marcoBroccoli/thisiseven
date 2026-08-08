#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    struct ConnectionsConnectedView: View {
        let partnerConnected: Bool

        var body: some View {
            ConnectionsSetupChrome.stepScreen {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 0) {
                        ConnectionsDrawnCheckmark()

                        Text("Your Gmail &\nthe calendar.")
                            .font(.system(size: 26, weight: .medium, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(EvenTokens.espresso)
                            .padding(.top, 20)

                        ConnectionsSetupChrome.italicNote(
                            "Your mailbox is connected to your inbox alone. The “Even” calendar it publishes to is the shared one — subscribe from either of your phones.",
                            size: 14.5
                        )
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 250)
                        .padding(.top, 12)

                        ConnectionsCalendarCallout()
                            .padding(.top, 22)

                        ConnectionsPartnerNote(partnerConnected: partnerConnected)
                            .padding(.top, 14)
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

    #Preview("Connections · connected · partner not connected") {
        ConnectionsView(store: ConnectionsPreviewSupport.connectedPartnerMissing())
    }
#endif

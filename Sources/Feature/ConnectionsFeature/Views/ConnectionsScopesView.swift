#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    @ViewAction(for: ConnectionsReducer.self)
    struct ConnectionsScopesView: View {
        @Bindable var store: StoreOf<ConnectionsReducer>

        var body: some View {
            ConnectionsSetupChrome.stepScreen {
                Text("What Even\ncan see.")
                    .font(.system(size: 31, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ConnectionsSetupChrome.italicNote(scopeSubtitle, size: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                VStack(spacing: 12) {
                    ConnectionsScopeCard(
                        systemImage: "tray",
                        title: "Gmail — read-only",
                        bodyText: "Even scans subject lines and previews for bills, renewals and appointments. It can't send, delete, or move anything.",
                        isOn: $store.gmailEnabled
                    )
                    ConnectionsScopeCard(
                        systemImage: "calendar",
                        title: "Calendar — read & write",
                        bodyText: "Lets Even create the shared “Even” calendar and add approved events with reminders.",
                        isOn: $store.calendarEnabled
                    )
                }
                .padding(.top, 26)

                ConnectionsSetupChrome.italicNote(
                    "Revoke either scope any time in Settings → Connections.",
                    size: 12.5
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
        }

        private var scopeSubtitle: String {
            let email = store.email ?? "your Google account"
            return "\(email) · both scopes read-only"
        }
    }

    #Preview("Connections · scopes") {
        ConnectionsView(store: ConnectionsPreviewSupport.scopes())
    }
#endif

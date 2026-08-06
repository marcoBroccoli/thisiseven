#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    @ViewAction(for: HouseholdSetupReducer.self)
    struct HouseholdJoinView: View {
        @Bindable var store: StoreOf<HouseholdSetupReducer>

        var body: some View {
            HouseholdSetupChrome.stepScreen {
                HouseholdSetupChrome.heroBlock(
                    title: "Enter the\ncode.",
                    subtitle: "Six characters, from your partner."
                )

                EvenTextField("Invite code", text: $store.inviteCode, accessibilityId: "invite-code")
                    .textInputAutocapitalization(.characters)
                    .padding(.top, 30)

                EvenTextField("Your name", text: $store.displayName, accessibilityId: "display-name-join")
                    .padding(.top, 26)
            } footer: {
                EvenPrimaryButton(
                    "Join household",
                    enabled: !store.inviteCode.isEmpty && !store.working,
                    accessibilityId: "join-household"
                ) {
                    send(.submitJoin)
                }
            }
        }
    }

    #Preview("Household · join") {
        HouseholdJoinView(store: HouseholdSetupPreviewSupport.join())
            .evenPaperBackground()
    }
#endif

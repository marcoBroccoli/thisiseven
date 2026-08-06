import ComposableArchitecture
import Design
import SwiftUI

@ViewAction(for: HouseholdSetupReducer.self)
struct HouseholdInviteRevealView: View {
    @Bindable var store: StoreOf<HouseholdSetupReducer>

    var body: some View {
        let code = store.inviteReveal ?? "————"

        HouseholdSetupChrome.stepScreen {
            HouseholdSetupChrome.heroBlock(
                eyebrow: inviteEyebrow,
                title: "Now, your\npartner.",
                subtitle: "One code. It works exactly once."
            )

            InviteCodeTiles(code: code)
                .padding(.top, 32)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("invite-code-label")
                .accessibilityLabel(code)

            SharePrimaryButton(title: "Share the code", item: code)
                .padding(.top, 24)
                .accessibilityIdentifier("invite-share")

            CalloutCard(
                eyebrow: "WHAT YOUR PARTNER DOES NEXT",
                message: "They install Even, choose “Join with a code”, and type this in. The moment they land, the code retires — a household holds exactly two."
            )
            .padding(.top, 20)
        } footer: {
            TextContinueLink(
                title: "CONTINUE — THE CODE STAYS ON TODAY",
                accessibilityId: "invite-continue"
            ) {
                send(.continueAfterInvite)
            }
        }
    }

    private var inviteEyebrow: String {
        let name = store.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "CREATED" }
        return "\(name.uppercased()) · CREATED"
    }
}

#Preview("Household · invite") {
    HouseholdInviteRevealView(store: HouseholdSetupPreviewSupport.inviteReveal())
        .evenPaperBackground()
}

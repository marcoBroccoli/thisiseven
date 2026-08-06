import ComposableArchitecture
import Design
import SwiftUI

@ViewAction(for: HouseholdSetupReducer.self)
struct HouseholdChoiceView: View {
    @Bindable var store: StoreOf<HouseholdSetupReducer>

    var body: some View {
        HouseholdSetupChrome.stepScreen {
            HouseholdSetupChrome.heroBlock(
                eyebrow: "SIGNED IN",
                title: "Set up your\nhousehold.",
                subtitle: "An Even household holds exactly two people."
            )

            VStack(spacing: 12) {
                PathChoiceButton(
                    title: "Start a new household",
                    subtitle: "YOU'LL GET A CODE TO HAND YOUR PARTNER",
                    emphasized: true,
                    accessibilityId: "Start our household"
                ) {
                    send(.createTapped, animation: EvenMotion.page)
                }

                PathChoiceButton(
                    title: "Join with a code",
                    subtitle: "YOUR PARTNER GAVE YOU SIX CHARACTERS",
                    emphasized: false,
                    accessibilityId: "mode-join"
                ) {
                    send(.joinTapped, animation: EvenMotion.page)
                }
            }
            .padding(.top, 28)
        }
    }
}

#Preview("Household · choice") {
    HouseholdChoiceView(store: HouseholdSetupPreviewSupport.choice())
        .evenPaperBackground()
}

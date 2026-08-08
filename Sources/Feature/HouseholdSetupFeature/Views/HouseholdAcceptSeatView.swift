#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    /// Taking a seat someone kept for you. One question — the name you'll go by
    /// in that household.
    @ViewAction(for: HouseholdSetupReducer.self)
    struct HouseholdAcceptSeatView: View {
        @Bindable var store: StoreOf<HouseholdSetupReducer>

        var body: some View {
            HouseholdSetupChrome.stepScreen {
                HouseholdSetupChrome.heroBlock(
                    eyebrow: eyebrow,
                    title: store.acceptingInvite?.householdName ?? "A household",
                    subtitle: "The other seat is yours if you want it."
                )

                EvenTextField(
                    "Your name",
                    text: $store.displayName,
                    accessibilityId: "display-name-accept"
                )
                .padding(.top, 34)

                HouseholdSetupChrome.italicNote(
                    "This is the name on your pan of the scale — what your partner sees on tasks.",
                    size: 12.5
                )
                .padding(.top, 10)
            } footer: {
                EvenPrimaryButton(
                    store.working ? "Taking the seat…" : "Take the seat",
                    enabled: !store.displayName.isEmpty && !store.working,
                    accessibilityId: "accept-seat"
                ) {
                    send(.submitAcceptInvite)
                }
            }
        }

        private var eyebrow: String {
            guard let name = store.acceptingInvite?.invitedByName, !name.isEmpty else {
                return "INVITED"
            }
            return "INVITED BY \(name.uppercased())"
        }
    }

    #Preview("Household · accept seat") {
        HouseholdAcceptSeatView(store: HouseholdSetupPreviewSupport.acceptInvite())
            .evenPaperBackground()
    }
#endif

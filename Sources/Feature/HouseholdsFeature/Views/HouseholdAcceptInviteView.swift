#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    /// Taking a seat needs one thing: the name you'll go by in *that* house.
    /// It starts as the name you already answer to.
    struct HouseholdAcceptInviteView: View {
        @Bindable var store: StoreOf<HouseholdsReducer>

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HouseholdsChrome.heroBlock(
                    eyebrow: invitedBy,
                    title: householdName,
                    subtitle: "The other seat is yours if you want it."
                )

                EvenTextField(
                    "Your name here",
                    text: $store.acceptDisplayName,
                    accessibilityId: "accept-display-name"
                )
                .padding(.top, 30)

                HouseholdsChrome.note(
                    "Tasks, mail and money stay inside this household — none of it reaches the others.",
                    size: 12.5
                )
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var householdName: String {
            store.acceptingInvite?.householdName ?? "A household"
        }

        private var invitedBy: String {
            guard let name = store.acceptingInvite?.invitedByName, !name.isEmpty else {
                return "INVITED"
            }
            return "INVITED BY \(name.uppercased())"
        }
    }

    #Preview("Households · accept") {
        HouseholdAcceptInviteView(store: HouseholdsPreviewSupport.accepting())
            .padding(.horizontal, HouseholdsChrome.pageHorizontal)
            .evenPaperBackground()
    }
#endif

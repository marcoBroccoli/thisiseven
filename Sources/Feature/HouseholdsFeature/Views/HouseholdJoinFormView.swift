#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    /// The other way in: somebody already holds a household and reads you its
    /// code. Same two questions as starting one — the code, and the name you go
    /// by *there*.
    struct HouseholdJoinFormView: View {
        @Bindable var store: StoreOf<HouseholdsReducer>

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HouseholdsChrome.heroBlock(
                    eyebrow: "SOMEONE ELSE’S PLACE",
                    title: "Enter the\ncode.",
                    subtitle: "Six characters, from whoever holds the free seat."
                )

                EvenTextField(
                    "Invite code",
                    text: $store.joinInviteCode,
                    accessibilityId: "join-invite-code"
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.top, 30)

                EvenTextField(
                    "Your name here",
                    text: $store.joinDisplayName,
                    accessibilityId: "join-display-name"
                )
                .padding(.top, 22)

                HouseholdsChrome.note(
                    "One name per household — you can go by something else in each.",
                    size: 12.5
                )
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #Preview("Households · join") {
        HouseholdJoinFormView(store: HouseholdsPreviewSupport.joining())
            .padding(.horizontal, HouseholdsChrome.pageHorizontal)
            .evenPaperBackground()
    }
#endif

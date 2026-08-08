#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    /// Same two questions onboarding asks — a household name, and the name you
    /// go by *there*. Nothing is shared with the households you already hold.
    struct HouseholdCreateFormView: View {
        @Bindable var store: StoreOf<HouseholdsReducer>

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HouseholdsChrome.heroBlock(
                    eyebrow: "ANOTHER PLACE",
                    title: "Name your\nhousehold.",
                    subtitle: "Both of these can change later."
                )

                EvenTextField(
                    "Household name",
                    text: $store.newHouseholdName,
                    accessibilityId: "new-household-name"
                )
                .padding(.top, 30)

                EvenTextField(
                    "Your name here",
                    text: $store.newDisplayName,
                    accessibilityId: "new-household-display-name"
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

    #Preview("Households · create") {
        HouseholdCreateFormView(store: HouseholdsPreviewSupport.creating())
            .padding(.horizontal, HouseholdsChrome.pageHorizontal)
            .evenPaperBackground()
    }
#endif

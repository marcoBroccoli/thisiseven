#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    @ViewAction(for: HouseholdSetupReducer.self)
    struct HouseholdCreateView: View {
        @Bindable var store: StoreOf<HouseholdSetupReducer>

        var body: some View {
            HouseholdSetupChrome.stepScreen {
                HouseholdSetupChrome.heroBlock(
                    title: "Name your\nhousehold.",
                    subtitle: "Both of these can change later."
                )

                EvenTextField("Household name", text: $store.name, accessibilityId: "household-name")
                    .padding(.top, 34)

                EvenTextField("Your name", text: $store.displayName, accessibilityId: "display-name-create")
                    .padding(.top, 26)

                HouseholdSetupChrome.italicNote(
                    "This is the name on your pan of the scale — what your partner sees on tasks.",
                    size: 12.5
                )
                .padding(.top, 10)
            } footer: {
                EvenPrimaryButton(
                    "Create household",
                    enabled: !store.name.isEmpty && !store.working,
                    accessibilityId: "create-household"
                ) {
                    send(.submitCreate)
                }
            }
        }
    }

    #Preview("Household · create") {
        HouseholdCreateView(store: HouseholdSetupPreviewSupport.create())
            .evenPaperBackground()
    }
#endif

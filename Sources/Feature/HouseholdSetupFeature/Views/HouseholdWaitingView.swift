import ComposableArchitecture
import Design
import SwiftUI

@ViewAction(for: HouseholdSetupReducer.self)
struct HouseholdWaitingView: View {
    @Bindable var store: StoreOf<HouseholdSetupReducer>

    var body: some View {
        HouseholdSetupChrome.stepScreen {
            brandMark

            HouseholdSetupChrome.italicNote(
                "All yours so far. Even starts mattering at two.",
                size: 13.5
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 34)

            WaitingPartnerCard(code: store.inviteReveal)
                .padding(.top, 18)

            HouseholdSetupChrome.italicNote(
                "The moment they join with this code, the beam gets its second pan and the week starts counting for both of you.",
                size: 14.5,
                color: HouseholdSetupChrome.inkMuted
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 270)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } footer: {
            EvenPrimaryButton("Continue") {
                send(.continueAfterInvite)
            }
        }
    }

    private var brandMark: some View {
        HStack(spacing: 7) {
            EvenScaleGlyph()
                .stroke(
                    EvenTokens.espresso,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 15, height: 15)
            Text("Even")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
        }
    }
}

#Preview("Household · waiting") {
    HouseholdWaitingView(store: HouseholdSetupPreviewSupport.waiting())
        .evenPaperBackground()
}

import ComposableArchitecture
import Design
import EvenCore
import SwiftUI

@ViewAction(for: HouseholdSetupReducer.self)
public struct HouseholdSetupView: View {
    @Bindable public var store: StoreOf<HouseholdSetupReducer>

    public init(store: StoreOf<HouseholdSetupReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            if let error = store.error {
                Text(error)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.terracotta)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 64)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .evenPaperBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch store.path {
        case .choice:
            Text("SIGNED IN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(EvenTokens.stone)
            Text("Set up your\nhousehold.")
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .padding(.top, 10)
            Spacer()
            // Keep the legacy E2E label as accessibility value; visible copy stays design-true.
            pathButton(
                title: "Create a household",
                subtitle: "You'll get a code to share",
                id: "Start our household"
            ) {
                send(.createTapped)
            }
            pathButton(
                title: "Join with a code",
                subtitle: "Your partner already started",
                id: "mode-join"
            ) {
                send(.joinTapped)
            }
            .padding(.top, 12)

        case .create:
            Text("Name your\nhousehold.")
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            EvenTextField("Household name", text: $store.name, accessibilityId: "household-name")
                .padding(.top, 24)
            EvenTextField("Your display name", text: $store.displayName, accessibilityId: "display-name-create")
                .padding(.top, 14)
            Spacer()
            EvenPrimaryButton(
                "Create — get the invite code",
                enabled: !store.name.isEmpty && !store.working,
                accessibilityId: "create-household"
            ) {
                send(.submitCreate)
            }

        case .inviteReveal:
            Text("Now, your\npartner.")
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            Text("Share this code so they can join.")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x6E6353))
                .padding(.top, 10)
            Text(store.inviteReveal ?? "————")
                .font(.system(size: 40, weight: .medium, design: .serif))
                .tracking(8)
                .foregroundStyle(EvenTokens.espresso)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(EvenTokens.paperCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.top, 20)
                .accessibilityIdentifier("invite-code-label")
            Spacer()
            EvenPrimaryButton("Continue", accessibilityId: "invite-continue") {
                send(.continueAfterInvite)
            }

        case .join:
            Text("Enter the\ncode.")
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            EvenTextField("Invite code", text: $store.inviteCode, accessibilityId: "invite-code")
                .padding(.top, 24)
            EvenTextField("Your display name", text: $store.displayName, accessibilityId: "display-name-join")
                .padding(.top, 14)
            Spacer()
            EvenPrimaryButton(
                "Join the household",
                enabled: !store.inviteCode.isEmpty && !store.working,
                accessibilityId: "join-household"
            ) {
                send(.submitJoin)
            }

        case .waiting:
            Spacer()
            Text("Waiting for\nyour partner.")
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            Text("They'll show up here the moment they join.")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x6E6353))
                .padding(.top, 10)
            Spacer()
            EvenPrimaryButton("Continue") { send(.continueAfterInvite) }
        }
    }

    private func pathButton(
        title: String,
        subtitle: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(hex: 0x6E6353))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(EvenTokens.espresso)
            }
            .padding(18)
            .background(EvenTokens.paperCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

#Preview("Household · flow") {
    HouseholdSetupView(store: HouseholdSetupPreviewSupport.flow())
}

#Preview("Household · choice") {
    HouseholdSetupView(store: HouseholdSetupPreviewSupport.choice())
}

#Preview("Household · create") {
    HouseholdSetupView(store: HouseholdSetupPreviewSupport.create())
}

#Preview("Household · invite") {
    HouseholdSetupView(store: HouseholdSetupPreviewSupport.inviteReveal())
}

#Preview("Household · join") {
    HouseholdSetupView(store: HouseholdSetupPreviewSupport.join())
}

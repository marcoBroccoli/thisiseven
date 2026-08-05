import ComposableArchitecture
import Design
import EvenCore
import HouseholdClient
import SwiftUI

@Reducer
public struct HouseholdSetupFeature {
    @ObservableState
    public struct State: Equatable {
        public var path: Path = .choice
        public var name: String = ""
        public var inviteCode: String = ""
        public var displayName: String = ""
        public var inviteReveal: String?
        public var error: String?
        public var working = false
        public init() {}
    }

    public enum Path: Equatable, Sendable {
        case choice, create, inviteReveal, join, waiting
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case createTapped
        case joinTapped
        case submitCreate
        case submitJoin
        case continueAfterInvite
        case createSucceeded(Household)
        case createFailed(String)
        case joinSucceeded(Household)
        case joinFailed(String)
        case delegate(Delegate)
        public enum Delegate: Equatable {
            case finished
        }
    }

    @Dependency(\.householdClient) var householdClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .createTapped:
                state.path = .create
                state.error = nil
                return .none
            case .joinTapped:
                state.path = .join
                state.error = nil
                return .none
            case .submitCreate:
                state.working = true
                let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = state.displayName.isEmpty ? "Me" : state.displayName
                return .run { [householdClient] send in
                    do {
                        try await send(.createSucceeded(await householdClient.create(name, display)))
                    } catch {
                        await send(.createFailed(String(describing: error)))
                    }
                }
            case .submitJoin:
                state.working = true
                let code = state.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = state.displayName.isEmpty ? "Me" : state.displayName
                return .run { [householdClient] send in
                    do {
                        try await send(.joinSucceeded(await householdClient.join(code, display)))
                    } catch {
                        await send(.joinFailed(String(describing: error)))
                    }
                }
            case let .createSucceeded(household):
                state.working = false
                state.inviteReveal = household.inviteCode
                state.path = .inviteReveal
                return .none
            case .joinSucceeded:
                state.working = false
                state.path = .waiting
                return .send(.delegate(.finished))
            case let .createFailed(message), let .joinFailed(message):
                state.working = false
                state.error = message
                return .none
            case .continueAfterInvite:
                return .send(.delegate(.finished))
            case .delegate:
                return .none
            }
        }
    }
}

public struct HouseholdSetupFeatureView: View {
    @Bindable public var store: StoreOf<HouseholdSetupFeature>

    public init(store: StoreOf<HouseholdSetupFeature>) {
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
        .background(EvenTokens.paperRaised.ignoresSafeArea())
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
                store.send(.createTapped)
            }
            pathButton(
                title: "Join with a code",
                subtitle: "Your partner already started",
                id: "mode-join"
            ) {
                store.send(.joinTapped)
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
                store.send(.submitCreate)
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
                store.send(.continueAfterInvite)
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
                store.send(.submitJoin)
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
            EvenPrimaryButton("Continue") { store.send(.continueAfterInvite) }
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

#Preview("Household · choice") {
    HouseholdSetupFeatureView(store: HouseholdSetupPreviewSupport.choice())
}

#Preview("Household · create") {
    HouseholdSetupFeatureView(store: HouseholdSetupPreviewSupport.create())
}

#Preview("Household · invite") {
    HouseholdSetupFeatureView(store: HouseholdSetupPreviewSupport.inviteReveal())
}

#Preview("Household · join") {
    HouseholdSetupFeatureView(store: HouseholdSetupPreviewSupport.join())
}

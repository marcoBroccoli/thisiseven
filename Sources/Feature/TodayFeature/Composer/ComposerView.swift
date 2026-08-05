import ComposableArchitecture
import Design
import EvenCore
import SwiftUI

@ViewAction(for: ComposerReducer.self)
public struct ComposerView: View {
    @Bindable public var store: StoreOf<ComposerReducer>
    let me: Member?
    let partner: Member?

    public init(store: StoreOf<ComposerReducer>, me: Member?, partner: Member?) {
        self.store = store
        self.me = me
        self.partner = partner
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(EvenTokens.espresso.opacity(0.14))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            HStack {
                Text("NEW TODO")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                Spacer()
                Button("✕") { send(.cancelTapped) }
                    .foregroundStyle(EvenTokens.stone)
            }
            .padding(.top, 12)

            TextField("What needs doing?", text: $store.title)
                .font(.system(size: 18, design: .serif))
                .padding(.top, 10)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    EvenTokens.espresso.opacity(0.16).frame(height: 1.5)
                }
                .accessibilityIdentifier("task-title")

            Text("OWNER")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ownerChip(me?.displayName ?? "Me", selected: store.ownerIsMe) {
                    send(.selectOwner(true))
                }
                if partner != nil {
                    ownerChip(partner?.displayName ?? "Partner", selected: !store.ownerIsMe) {
                        send(.selectOwner(false))
                    }
                }
            }
            .padding(.top, 6)

            Text("HEFT — HOW MUCH THIS WEIGHS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(1 ... 3, id: \.self) { w in
                    Button {
                        send(.selectWeight(w))
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 2.5) {
                                ForEach(0 ..< w, id: \.self) { _ in
                                    Circle().fill(EvenTokens.espresso).frame(width: 6, height: 6)
                                }
                            }
                            .frame(height: 14)
                            Text(w == 1 ? "Light" : w == 2 ? "Medium" : "Heavy")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    store.weight == w ? EvenTokens.espresso : EvenTokens.espresso.opacity(0.16),
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(EvenTokens.espresso)
                }
            }
            .padding(.top, 6)

            EvenPrimaryButton(
                "Add to Today",
                enabled: !store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityId: "task-save"
            ) {
                send(.saveTapped)
            }
            .padding(.top, 20)
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 20)
        .evenPaperBackground(EvenTokens.paperCard)
        .presentationDetents([.medium, .large])
    }

    private func ownerChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(selected ? EvenTokens.espresso : EvenTokens.paperCard)
                .foregroundStyle(selected ? EvenTokens.paperCard : EvenTokens.espresso)
                .overlay(
                    Capsule().stroke(EvenTokens.espresso.opacity(selected ? 0 : 0.16), lineWidth: 1.5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

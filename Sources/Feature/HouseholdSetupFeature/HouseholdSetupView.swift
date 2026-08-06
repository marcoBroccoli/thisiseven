#if os(iOS)
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
            NavigationStack {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Paper on the stack *content* (Onboarding / Inbox pattern).
                    .evenPaperBackground()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent }
                    .animation(EvenMotion.reveal, value: store.showsBack)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                    .tint(EvenTokens.espresso)
            }
        }

        @ToolbarContentBuilder
        private var toolbarContent: some ToolbarContent {
            if store.showsBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        send(.backTapped, animation: EvenMotion.page)
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("household-back")
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -8)),
                            removal: .opacity.combined(with: .offset(x: -8))
                        )
                    )
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Your household")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
            }
        }

        private var pageContent: some View {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    pathContent
                        .id(store.path)
                        .transition(EvenMotion.fadeUp)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if let error = store.error {
                    errorBanner(error)
                }
            }
            .padding(.horizontal, HouseholdSetupChrome.horizontalInset)
            .padding(.top, HouseholdSetupChrome.topInset)
            .padding(.bottom, HouseholdSetupChrome.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(EvenMotion.page, value: store.path)
            .animation(EvenMotion.reveal, value: store.error)
            .animation(EvenMotion.reveal, value: store.working)
        }

        @ViewBuilder
        private var pathContent: some View {
            switch store.path {
            case .choice:
                HouseholdChoiceView(store: store)
            case .create:
                HouseholdCreateView(store: store)
            case .inviteReveal:
                HouseholdInviteRevealView(store: store)
            case .join:
                HouseholdJoinView(store: store)
            case .waiting:
                HouseholdWaitingView(store: store)
            }
        }

        private func errorBanner(_ message: String) -> some View {
            let centered = store.path == .join
            return Text(message)
                .font(.system(size: 13.5, design: .serif))
                .italic()
                .multilineTextAlignment(centered ? .center : .leading)
                .foregroundStyle(EvenTokens.terracotta)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.top, 14)
                .transition(EvenMotion.fadeUp)
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
#endif

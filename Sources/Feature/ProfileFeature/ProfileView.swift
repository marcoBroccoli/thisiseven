#if os(iOS)
    import ComposableArchitecture
    import ConnectionsFeature
    import Design
    import EvenCore
    import IGTabBar
    import SwiftUI
    import UIKit
    import VisualEffects

    @ViewAction(for: ProfileReducer.self)
    public struct ProfileView: View {
        @Bindable public var store: StoreOf<ProfileReducer>
        private var tabBarProgress: Binding<CGFloat>?

        public init(
            store: StoreOf<ProfileReducer>,
            tabBarProgress: Binding<CGFloat>? = nil
        ) {
            self.store = store
            self.tabBarProgress = tabBarProgress
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    Group {
                        if store.isLoading && store.me == nil {
                            ProfileSkeleton()
                                .loading(true)
                        } else {
                            profileContent
                        }
                    }
                    .padding(.horizontal, ProfileLayout.pageHorizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .evenScrollOnPaper()
                .adoptForIGTabBar(tabBarProgress)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        EvenBrandMark()
                    }
                }
                .evenPaperNavigationChrome()
                .alert(
                    "Sign out?",
                    isPresented: Binding(
                        get: { store.confirmSignOut },
                        set: { if !$0 { send(.cancelSignOut) } }
                    )
                ) {
                    Button("Cancel", role: .cancel) { send(.cancelSignOut) }
                    Button("Sign out", role: .destructive) { send(.confirmSignOut) }
                } message: {
                    Text("You’ll need to sign in again to see the household.")
                }
            }
            .onAppear { send(.appear) }
            .evenToastHost()
        }

        private var profileContent: some View {
            VStack(alignment: .leading, spacing: ProfileLayout.sectionGap) {
                VStack(alignment: .leading, spacing: 10) {
                    ProfileSectionHeader(title: "YOU")
                    ProfileYouCard(
                        displayName: $store.draftDisplayName,
                        memberId: store.me?.id ?? PreviewData.adaId,
                        color: store.me?.color ?? .clay,
                        hasAvatar: store.me?.hasAvatar ?? false,
                        localAvatarJPEG: store.localAvatarJPEG,
                        nameError: store.nameError,
                        isSaving: store.isSaving,
                        onCommitName: { send(.commitDisplayName) },
                        onSelectColor: { send(.selectColor($0)) },
                        onPickJPEG: { send(.pickAvatarJPEG($0)) },
                        onRemoveAvatar: { send(.removeAvatar) }
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProfileSectionHeader(title: "HOUSEHOLD")
                    ProfileHouseholdCard(
                        householdName: store.householdName,
                        partner: store.partner,
                        inviteCode: store.inviteCode,
                        onCopyInvite: copyInvite
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProfileSectionHeader(title: "CONNECTIONS")
                    if store.googleConnected {
                        ConnectionsSettingsView(
                            store: store.scope(state: \.connections, action: \.connections)
                        )
                    } else {
                        ProfileConnectGoogleCard(
                            working: store.connections.working || store.connections.isCheckingStatus,
                            onConnect: { send(.connectGoogleTapped) }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProfileSectionHeader(title: "ACCOUNT")
                    ProfileSignOutButton { send(.signOutTapped) }
                }
            }
        }

        private func copyInvite() {
            guard !store.inviteCode.isEmpty else { return }
            UIPasteboard.general.string = store.inviteCode
            send(.inviteCopied)
        }
    }

    #Preview("Profile · populated") {
        ProfileView(store: ProfilePreviewSupport.populated())
    }

    #Preview("Profile · loading") {
        ProfileView(store: ProfilePreviewSupport.loading())
    }
#endif

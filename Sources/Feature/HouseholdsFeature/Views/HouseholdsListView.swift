#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI
    import UIKit
    import VisualEffects

    @ViewAction(for: HouseholdsReducer.self)
    struct HouseholdsListView: View {
        @Bindable var store: StoreOf<HouseholdsReducer>

        var body: some View {
            ZStack(alignment: .top) {
                if showsSkeleton {
                    HouseholdsSkeleton()
                        .loading(true)
                        .transition(EvenMotion.fadeOnly)
                } else {
                    loaded
                        .transition(EvenMotion.fadeUp)
                }
            }
            .animation(EvenMotion.reveal, value: showsSkeleton)
        }

        private var showsSkeleton: Bool {
            store.isLoading && store.households.isEmpty && store.invites.isEmpty
        }

        private var loaded: some View {
            VStack(alignment: .leading, spacing: HouseholdsChrome.sectionGap) {
                if !store.invites.isEmpty {
                    invitesSection
                }

                householdsSection

                // Redundant next to the empty state, which says the same thing
                // in fewer words.
                if !store.households.isEmpty {
                    HouseholdsChrome.note(
                        "A household holds two people. You can keep as many as you like — nothing crosses between them.",
                        size: 12.5
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        private var invitesSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                HouseholdsChrome.eyebrow("WAITING FOR YOU")
                ForEach(store.invites) { invite in
                    HouseholdInviteCard(
                        invite: invite,
                        isBusy: store.busyInviteID == invite.id,
                        onAccept: { send(.acceptTapped(invite.id), animation: EvenMotion.page) },
                        onDecline: { send(.declineTapped(invite.id), animation: EvenMotion.reveal) }
                    )
                }
            }
        }

        private var householdsSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                HouseholdsChrome.eyebrow("YOUR HOUSEHOLDS")

                if store.households.isEmpty {
                    HouseholdsChrome.note("No household yet — start one below, or take a seat above.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(store.households) { row in
                        HouseholdRowCard(
                            row: row,
                            isActive: store.effectiveActiveID == row.id,
                            isExpanded: store.expandedHouseholdID == row.id,
                            isBusy: store.busyHouseholdID == row.id,
                            inviteEmail: $store.inviteEmail,
                            onSelect: { send(.selectHousehold(row.id), animation: EvenMotion.reveal) },
                            onToggleExpanded: { send(.toggleExpanded(row.id), animation: EvenMotion.reveal) },
                            onCopyCode: { copyCode(row.inviteCode) },
                            onInvite: { send(.submitInvite(row.id)) },
                            onRevoke: { send(.revokeInvite(row.id), animation: EvenMotion.reveal) }
                        )
                    }
                }
            }
        }

        private func copyCode(_ code: String) {
            guard !code.isEmpty else { return }
            UIPasteboard.general.string = code
            send(.inviteCodeCopied)
        }
    }

    #Preview("Households · list body") {
        HouseholdsListView(store: HouseholdsPreviewSupport.populated())
            .padding(.horizontal, HouseholdsChrome.pageHorizontal)
            .evenPaperBackground()
    }
#endif

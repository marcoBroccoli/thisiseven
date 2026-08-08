#if os(iOS)
    import Design
    import EvenCore
    import SwiftUI

    /// One place you belong to. Tapping the card switches to it; the chevron
    /// opens the seat controls (invite code, the address on the free seat).
    struct HouseholdRowCard: View {
        let row: HouseholdRow
        let isActive: Bool
        let isExpanded: Bool
        let isBusy: Bool
        @Binding var inviteEmail: String
        let onSelect: () -> Void
        let onToggleExpanded: () -> Void
        let onCopyCode: () -> Void
        let onInvite: () -> Void
        let onRevoke: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                header

                if isExpanded {
                    EvenTokens.espresso.opacity(0.1)
                        .frame(height: 1)
                        .padding(.top, 14)

                    seatControls
                        .padding(.top, 14)
                }
            }
            .padding(HouseholdsChrome.cardPadding)
            .householdsCardChrome(accented: isActive)
            .accessibilityIdentifier("household-\(row.name)")
        }

        private var header: some View {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name)
                            .font(.system(size: 18, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            Text(row.seatsLine)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(EvenTokens.espresso.opacity(0.5))

                            if row.isOwner {
                                Text("YOUR PLACE")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(EvenTokens.terracotta)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        EvenTokens.terracotta.opacity(0.1),
                                        in: Capsule()
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.evenPlain)
                .allowsHitTesting(!isBusy && !isActive)
                .accessibilityIdentifier("switch-to-\(row.name)")
                .accessibilityAddTraits(isActive ? .isSelected : [])

                activeMark

                Button(action: onToggleExpanded) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvenTokens.espresso.opacity(0.45))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.evenPlain)
                .accessibilityLabel(isExpanded ? "Hide seat" : "Show seat")
                .accessibilityIdentifier("expand-\(row.name)")
            }
        }

        @ViewBuilder
        private var activeMark: some View {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(EvenTokens.stone)
                    .frame(width: 26, height: 26)
            } else if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(EvenTokens.paperCard)
                    .frame(width: 24, height: 24)
                    .background(EvenTokens.terracotta, in: Circle())
                    .accessibilityLabel("Currently open")
                    .accessibilityIdentifier("active-\(row.name)")
            }
        }

        private var seatControls: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HouseholdsChrome.fieldLabel("INVITE CODE")
                        Text(row.inviteCode)
                            .font(.system(size: 19, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                    }
                    Spacer(minLength: 8)
                    Button("Copy", action: onCopyCode)
                        .font(.system(size: 13.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(EvenTokens.espresso.opacity(0.08), in: Capsule())
                        .buttonStyle(.evenPlain)
                        .accessibilityIdentifier("copy-code-\(row.name)")
                }

                if let pending = row.pendingInviteEmail {
                    pendingInviteRow(pending)
                } else if row.hasFreeSeat {
                    inviteField
                } else {
                    HouseholdsChrome.note("Both seats taken — this household is full.")
                }
            }
        }

        private func pendingInviteRow(_ email: String) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HouseholdsChrome.fieldLabel("SEAT HELD FOR")
                HStack(spacing: 10) {
                    Text(email)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Withdraw", action: onRevoke)
                        .font(.system(size: 13.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.terracotta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(EvenTokens.terracotta.opacity(0.08), in: Capsule())
                        .buttonStyle(.evenPlain)
                        .allowsHitTesting(!isBusy)
                        .accessibilityIdentifier("revoke-invite-\(row.name)")
                }
                HouseholdsChrome.note(
                    "They’ll find it waiting the moment they sign in with that address.",
                    size: 12.5
                )
            }
        }

        private var inviteField: some View {
            VStack(alignment: .leading, spacing: 10) {
                EvenTextField(
                    "Invite by email",
                    text: $inviteEmail,
                    accessibilityId: "invite-email-\(row.name)"
                )
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(onInvite)

                Button(action: onInvite) {
                    Text(isBusy ? "Sending…" : "Send invite")
                        .font(.system(size: 14.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(EvenTokens.espresso, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.evenPlain)
                .allowsHitTesting(!isBusy && !inviteEmail.isEmpty)
                .accessibilityIdentifier("send-invite-\(row.name)")

                HouseholdsChrome.note(
                    "No mail goes out — the invite simply waits for them in Even.",
                    size: 12.5
                )
            }
        }
    }

    /// An invite addressed to you. Two answers, both one tap away.
    struct HouseholdInviteCard: View {
        let invite: HouseholdInvite
        let isBusy: Bool
        let onAccept: () -> Void
        let onDecline: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(invite.householdName)
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text("\(invite.invitedByName) kept a seat for you")
                        .font(.system(size: 13.5, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.stone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button(action: onAccept) {
                        Text("Accept")
                            .font(.system(size: 14.5, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.paperRaised)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(isBusy ? EvenTokens.stone : EvenTokens.espresso, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.evenPlain)
                    .allowsHitTesting(!isBusy)
                    .accessibilityIdentifier("accept-invite-\(invite.householdName)")

                    Button(action: onDecline) {
                        Text("Decline")
                            .font(.system(size: 14.5, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .overlay(Capsule().stroke(EvenTokens.espresso.opacity(0.35), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.evenPlain)
                    .allowsHitTesting(!isBusy)
                    .accessibilityIdentifier("decline-invite-\(invite.householdName)")
                }
            }
            .padding(HouseholdsChrome.cardPadding)
            .householdsCardChrome()
        }
    }

    /// First frame while the list is on its way — mirrors the loaded layout.
    struct HouseholdsSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(HouseholdsSkeletonData.cardHeights, id: \.self) { height in
                    RoundedRectangle(cornerRadius: HouseholdsChrome.cardRadius, style: .continuous)
                        .fill(EvenTokens.espresso.opacity(0.08))
                        .frame(height: height)
                }
            }
        }
    }

    /// Feature-local placeholder shapes — never `PreviewData` in production UI.
    enum HouseholdsSkeletonData {
        static let cardHeights: [CGFloat] = [92, 92, 128]
    }
#endif

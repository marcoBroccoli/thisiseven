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

    // MARK: - Chrome

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
        .padding(.horizontal, ViewConfig.horizontalInset)
        .padding(.top, ViewConfig.topInset)
        .padding(.bottom, ViewConfig.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(EvenMotion.page, value: store.path)
        .animation(EvenMotion.reveal, value: store.error)
        .animation(EvenMotion.reveal, value: store.working)
    }

    @ViewBuilder
    private var pathContent: some View {
        switch store.path {
        case .choice:
            choiceContent
        case .create:
            createContent
        case .inviteReveal:
            inviteRevealContent
        case .join:
            joinContent
        case .waiting:
            waitingContent
        }
    }

    // MARK: - Paths

    private var choiceContent: some View {
        stepScreen {
            heroBlock(
                eyebrow: "SIGNED IN",
                title: "Set up your\nhousehold.",
                subtitle: "An Even household holds exactly two people."
            )

            VStack(spacing: 12) {
                PathChoiceButton(
                    title: "Start a new household",
                    subtitle: "YOU'LL GET A CODE TO HAND YOUR PARTNER",
                    emphasized: true,
                    accessibilityId: "Start our household"
                ) {
                    send(.createTapped, animation: EvenMotion.page)
                }

                PathChoiceButton(
                    title: "Join with a code",
                    subtitle: "YOUR PARTNER GAVE YOU SIX CHARACTERS",
                    emphasized: false,
                    accessibilityId: "mode-join"
                ) {
                    send(.joinTapped, animation: EvenMotion.page)
                }
            }
            .padding(.top, 28)
        }
    }

    private var createContent: some View {
        stepScreen {
            heroBlock(
                title: "Name your\nhousehold.",
                subtitle: "Both of these can change later."
            )

            EvenTextField("Household name", text: $store.name, accessibilityId: "household-name")
                .padding(.top, 34)

            EvenTextField("Your name", text: $store.displayName, accessibilityId: "display-name-create")
                .padding(.top, 26)

            italicNote(
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

    private var inviteRevealContent: some View {
        let code = store.inviteReveal ?? "————"

        return stepScreen {
            heroBlock(
                eyebrow: inviteEyebrow,
                title: "Now, your\npartner.",
                subtitle: "One code. It works exactly once."
            )

            InviteCodeTiles(code: code)
                .padding(.top, 32)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("invite-code-label")
                .accessibilityLabel(code)

            SharePrimaryButton(title: "Share the code", item: code)
                .padding(.top, 24)
                .accessibilityIdentifier("invite-share")

            CalloutCard(
                eyebrow: "WHAT YOUR PARTNER DOES NEXT",
                message: "They install Even, choose “Join with a code”, and type this in. The moment they land, the code retires — a household holds exactly two."
            )
            .padding(.top, 20)
        } footer: {
            TextContinueLink(
                title: "CONTINUE — THE CODE STAYS ON TODAY",
                accessibilityId: "invite-continue"
            ) {
                send(.continueAfterInvite)
            }
        }
    }

    private var joinContent: some View {
        stepScreen {
            heroBlock(
                title: "Enter the\ncode.",
                subtitle: "Six characters, from your partner."
            )

            EvenTextField("Invite code", text: $store.inviteCode, accessibilityId: "invite-code")
                .textInputAutocapitalization(.characters)
                .padding(.top, 30)

            EvenTextField("Your name", text: $store.displayName, accessibilityId: "display-name-join")
                .padding(.top, 26)
        } footer: {
            EvenPrimaryButton(
                "Join household",
                enabled: !store.inviteCode.isEmpty && !store.working,
                accessibilityId: "join-household"
            ) {
                send(.submitJoin)
            }
        }
    }

    private var waitingContent: some View {
        stepScreen {
            brandMark

            italicNote("All yours so far. Even starts mattering at two.", size: 13.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 34)

            WaitingPartnerCard(code: store.inviteReveal)
                .padding(.top, 18)

            italicNote(
                "The moment they join with this code, the beam gets its second pan and the week starts counting for both of you.",
                size: 14.5,
                color: ViewConfig.inkMuted
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

    // MARK: - Shared pieces

    private var inviteEyebrow: String {
        let name = store.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "CREATED" }
        return "\(name.uppercased()) · CREATED"
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

    private func heroBlock(
        eyebrow: String? = nil,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(EvenTokens.stone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(title)
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, eyebrow == nil ? 0 : 10)

            italicNote(subtitle, size: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
    }

    private func italicNote(
        _ text: String,
        size: CGFloat,
        color: Color = EvenTokens.stone
    ) -> some View {
        Text(text)
            .font(.system(size: size, design: .serif))
            .italic()
            .foregroundStyle(color)
    }

    private func stepScreen<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        stepScreen(content: content, footer: { EmptyView() })
    }

    private func stepScreen<Content: View, Footer: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Spacer(minLength: 0)
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private enum ViewConfig {
        static let horizontalInset: CGFloat = 28
        static let topInset: CGFloat = 12
        static let bottomInset: CGFloat = 40
        static let inkMuted = Color(hex: 0x6E6353)
    }
}

// MARK: - Private components

private struct PathChoiceButton: View {
    let title: String
    let subtitle: String
    let emphasized: Bool
    let accessibilityId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(EvenTokens.stone)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EvenTokens.espresso)
            }
            .padding(18)
            .background(emphasized ? EvenTokens.paperCard : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }
}

private struct InviteCodeTiles: View {
    let code: String

    var body: some View {
        let chars = Array(code)
        GeometryReader { geo in
            let count = max(chars.count, 1)
            let spacing = HouseholdSetupView.TileMetrics.spacing
            let tileWidth = min(
                HouseholdSetupView.TileMetrics.width,
                max(28, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            )
            let tileHeight = tileWidth * (
                HouseholdSetupView.TileMetrics.height / HouseholdSetupView.TileMetrics.width
            )
            let fontSize = min(27, tileWidth * 0.6)

            HStack(spacing: spacing) {
                ForEach(Array(chars.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: fontSize, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .frame(width: tileWidth, height: tileHeight)
                        .background(EvenTokens.paperCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(EvenTokens.espresso.opacity(0.2), lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: HouseholdSetupView.TileMetrics.height)
        .frame(maxWidth: .infinity)
    }
}

private struct SharePrimaryButton: View {
    let title: String
    let item: String

    var body: some View {
        ShareLink(item: item) {
            HStack(spacing: 9) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .serif))
            }
            .foregroundStyle(EvenTokens.paperRaised)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(EvenTokens.espresso)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TextContinueLink: View {
    let title: String
    let accessibilityId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(EvenTokens.stone)
                .underline(pattern: .solid, color: EvenTokens.stone.opacity(0.55))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(accessibilityId)
    }
}

private struct CalloutCard: View {
    let eyebrow: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
            Text(message)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(Color(hex: 0x6E6353))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EvenTokens.espresso.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct WaitingPartnerCard: View {
    let code: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("YOUR PARTNER ISN'T IN YET")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                Spacer(minLength: 0)
                Circle()
                    .fill(EvenTokens.pine.opacity(0.5))
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 12) {
                Text(code ?? "————")
                    .font(.system(size: 25, weight: .medium, design: .serif))
                    .tracking(5.5)
                    .foregroundStyle(EvenTokens.espresso)
                Spacer(minLength: 0)
                if let code {
                    ShareLink(item: code) {
                        Text("RESEND")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(EvenTokens.paperRaised)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(EvenTokens.espresso)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(EvenTokens.paperCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension HouseholdSetupView {
    /// Shared by `InviteCodeTiles` (private nested access).
    enum TileMetrics {
        static let width: CGFloat = 44
        static let height: CGFloat = 58
        static let spacing: CGFloat = 8
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

import SwiftUI
import EvenCore

// Profile — reached from the toolbar avatar chip. Modest by design: who you
// are, the household, appearance, the Google connection, and the way out.

struct ProfileView: View {
    @Bindable var model: AppModel
    @Binding var isDark: Bool
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var connector = GoogleConnector()
    @State private var connecting = false
    @State private var signingOut = false

    var body: some View {
        SheetChrome(title: "PROFILE") {
            if let me = model.me {
                HStack(spacing: 12) {
                    OwnerChip(member: me, palette: palette, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.displayName)
                            .font(EvenFont.serif(20, .medium))
                            .foregroundStyle(palette.ink)
                        Text(me.color == .clay ? "CLAY SIDE OF THE SCALE" : "TEAL SIDE OF THE SCALE")
                            .capsLabel(8.5, tracking: 1.3)
                            .foregroundStyle(palette.member(me.color))
                    }
                }
            }

            if let household = model.household {
                section("HOUSEHOLD") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(household.name)
                                .font(EvenFont.serif(15))
                                .foregroundStyle(palette.ink)
                            Text("INVITE CODE · \(household.inviteCode)")
                                .capsLabel(8.5, tracking: 1.2)
                                .foregroundStyle(palette.sub)
                        }
                        Spacer()
                        ShareLink(item: "Join our household on Even — invite code \(household.inviteCode)") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(palette.sub)
                        }
                    }
                    Text(model.partner.map { "With \($0.displayName)." } ?? "Waiting for your partner to join.")
                        .font(EvenFont.serif(12.5, italic: true))
                        .foregroundStyle(palette.sub)
                }
            }

            section("APPEARANCE") {
                Button {
                    isDark.toggle()
                } label: {
                    HStack {
                        Text(isDark ? "Dark paper" : "Light paper")
                            .font(EvenFont.serif(15))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Image(systemName: isDark ? "sun.max" : "moon")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.sub)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .accessibilityIdentifier("dark-toggle")
            }

            section("GOOGLE") {
                if model.googleStatus?.connected == true {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .font(EvenFont.serif(15))
                                .foregroundStyle(palette.ink)
                            if let email = model.googleStatus?.email {
                                Text(email.uppercased())
                                    .capsLabel(8.5, tracking: 0.8)
                                    .foregroundStyle(palette.sub)
                            }
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(palette.teal)
                    }
                } else if GoogleConnectConfig.isEnabled {
                    GhostButton(title: connecting ? "Connecting…" : "Connect Google") {
                        guard !connecting else { return }
                        connecting = true
                        Task {
                            _ = await connector.connect(model: model)
                            connecting = false
                        }
                    }
                } else {
                    Text("Google connection isn't configured on this build.")
                        .font(EvenFont.serif(12.5, italic: true))
                        .foregroundStyle(palette.sub)
                }
            }

            Button {
                guard !signingOut else { return }
                signingOut = true
                Task {
                    await model.session.signOut()
                    dismiss()
                }
            } label: {
                Text("SIGN OUT")
                    .capsLabel(10, tracking: 1.4)
                    .foregroundStyle(palette.clay)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(palette.clay.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).capsLabel(9, tracking: 1.5).foregroundStyle(palette.sub)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

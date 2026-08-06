import ComposableArchitecture
import Design
import SwiftUI

/// Design 04 · manage connections (Settings entry — not part of setup path).
@ViewAction(for: ConnectionsReducer.self)
struct ConnectionsSettingsView: View {
    @Bindable var store: StoreOf<ConnectionsReducer>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connections")
                .font(.system(size: 27, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 12) {
                googleCard

                ConnectionsSetupChrome.italicNote(
                    "Disconnecting stops new drafts. Approved tasks and past events stay.",
                    size: 12.5
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, ConnectionsSetupChrome.topInset)
        .padding(.bottom, ConnectionsSetupChrome.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var googleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                EvenGoogleGMark()
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(googleTitle)
                        .font(.system(size: 15.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                    Text("CONNECTED")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(EvenTokens.pine)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            EvenTokens.espresso.opacity(0.1)
                .frame(height: 1)
                .padding(.top, 14)

            VStack(spacing: 10) {
                scopeToggleRow("Gmail — read-only", isOn: $store.gmailEnabled)
                scopeToggleRow("Calendar — read & write", isOn: $store.calendarEnabled)
            }
            .padding(.top, 12)

            Button {
                send(.disconnectTapped)
            } label: {
                Text(disconnectTitle)
                    .font(.system(size: 14.5, weight: .medium, design: .serif))
                    .contentTransition(.numericText())
                    .animation(EvenMotion.ctaSwap, value: disconnectTitle)
                    .foregroundStyle(EvenTokens.terracotta)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(EvenTokens.terracotta, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!store.working)
            .padding(.top, 14)
            .accessibilityIdentifier("Disconnect Google")
        }
        .padding(16)
        .background(EvenTokens.paperCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var disconnectTitle: String {
        store.working ? "Disconnecting…" : "Disconnect Google"
    }

    private var googleTitle: String {
        if let email = store.email {
            "Google — \(email)"
        } else {
            "Google"
        }
    }

    private func scopeToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(EvenTokens.espresso)
        }
    }
}

#Preview("Connections · settings") {
    ConnectionsSettingsView(store: ConnectionsPreviewSupport.settings())
        .evenPaperBackground()
}

#Preview("Connections · settings · disconnect slow") {
    ConnectionsSettingsView(store: ConnectionsPreviewSupport.flowDisconnectSlow())
        .evenPaperBackground()
}

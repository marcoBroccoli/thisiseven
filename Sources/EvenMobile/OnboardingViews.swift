import SwiftUI
import EvenCore
import AuthenticationServices
import CryptoKit

// Onboarding — sign in, then create or join the household. Same paper
// language as the app; not in the design file, so kept quiet and minimal.

struct OnboardingFlow: View {
    let session: SessionStore
    @Environment(\.palette) private var palette

    var body: some View {
        switch session.phase {
        case .needsHousehold:
            HouseholdSetupView(session: session)
        default:
            WelcomeView(session: session)
        }
    }
}

// MARK: - Welcome / sign-in

struct WelcomeView: View {
    let session: SessionStore
    @Environment(\.palette) private var palette
    @State private var rawNonce = ""
    @State private var errorText: String?
    @State private var working = false
    @State private var showDebugAuth = false

    // Launch choreography: glyph draws itself, then the wordmark, tagline
    // and options land in turn — settle, don't fade.
    @State private var glyphProgress: CGFloat = 0
    @State private var glyphBobbing = false
    @State private var showTitle = false
    @State private var showTagline = false
    @State private var showOptions = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ScaleGlyph()
                .trim(from: 0, to: glyphProgress)
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 44, height: 44)
                .offset(y: glyphBobbing ? -3 : 0)
                .animation(glyphBobbing
                           ? .easeInOut(duration: 2).repeatForever(autoreverses: true)
                           : .default,
                           value: glyphBobbing)

            Text("Even")
                .font(EvenFont.serif(40, .semibold, italic: true))
                .foregroundStyle(palette.ink)
                .padding(.top, 10)
                .landing(showTitle)

            Text("The house, weighed honestly.")
                .font(EvenFont.serif(15, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 6)
                .landing(showTagline)

            Spacer()

            Group {
                if let errorText {
                    Text(errorText)
                        .font(EvenFont.serif(13, italic: true))
                        .foregroundStyle(palette.clay)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }

                SignInWithAppleButton(.signIn) { request in
                    rawNonce = Self.randomNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(rawNonce)
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(working)

                #if DEBUG
                Button {
                    showDebugAuth = true
                } label: {
                    Text("DEV — EMAIL SIGN-IN")
                        .capsLabel(9, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .padding(.top, 14)
                }
                .sheet(isPresented: $showDebugAuth) {
                    DebugAuthSheet(session: session)
                }
                .accessibilityIdentifier("dev-email-signin")
                #endif

                Text("Two people, one household. Your data stays on your own server.")
                    .font(EvenFont.serif(11.5, italic: true))
                    .foregroundStyle(palette.sub)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
            }
            .landing(showOptions)
        }
        .padding(.horizontal, 34)
        .onAppear { choreograph() }
    }

    private func choreograph() {
        guard glyphProgress == 0 else { return }
        withAnimation(.easeInOut(duration: 0.9)) { glyphProgress = 1 }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.75)) { showTitle = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(1.05)) { showTagline = true }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(1.4)) { showOptions = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { glyphBobbing = true }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorText = "Apple didn't return a usable identity."
                return
            }
            working = true
            Task {
                do {
                    try await session.signInWithApple(identityToken: token, rawNonce: rawNonce)
                } catch {
                    errorText = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed."
                }
                working = false
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorText = "Sign in with Apple failed. Try again."
            }
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#if DEBUG
/// Simulator-friendly auth: email+password accounts on our GoTrue
/// (autoconfirmed). Debug builds only — never ships.
struct DebugAuthSheet: View {
    let session: SessionStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    @State private var working = false

    var body: some View {
        SheetChrome(title: "DEV EMAIL SIGN-IN — DEBUG ONLY") {
            UnderlineField(placeholder: "email@example.com", text: $email, serifSize: 15, id: "auth-email")
            SecureField("password", text: $password)
                .font(EvenFont.serif(15))
                .textFieldStyle(.plain)
                .accessibilityIdentifier("auth-password")
            Rectangle().fill(palette.line).frame(height: 1.5)

            if let errorText {
                Text(errorText)
                    .font(EvenFont.serif(12.5, italic: true))
                    .foregroundStyle(palette.clay)
            }

            HStack(spacing: 8) {
                GhostButton(title: "Sign up") { authenticate(signUp: true) }
                    .accessibilityIdentifier("auth-signup")
                PrimaryButton(title: working ? "…" : "Sign in", enabled: !working) {
                    authenticate(signUp: false)
                }
                .accessibilityIdentifier("auth-signin")
            }
        }
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .autocorrectionDisabled()
    }

    private func authenticate(signUp: Bool) {
        working = true
        errorText = nil
        Task {
            do {
                if signUp {
                    try await session.signUp(email: email, password: password)
                } else {
                    try await session.signIn(email: email, password: password)
                }
                dismiss()
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? "Failed."
            }
            working = false
        }
    }
}
#endif

private extension View {
    /// The design's fadeUp: rise 8pt and appear.
    func landing(_ shown: Bool) -> some View {
        self.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
    }
}

// MARK: - Onboarding progress

/// Post-sign-in progress: household → google. Thin capsule segments in the
/// app's tones, current-step caps label underneath. Hidden when there is
/// only one step (Google connect disabled).
struct OnboardingStepper: View {
    @Environment(\.palette) private var palette
    let step: Int
    let label: String

    private var total: Int { GoogleConnectConfig.isEnabled ? 2 : 1 }

    var body: some View {
        if total > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(1...total, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? AnyShapeStyle(palette.ink)
                                            : AnyShapeStyle(palette.faint))
                            .frame(height: 3)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: step)
                Text("STEP \(step) OF \(total) · \(label)")
                    .capsLabel(9, tracking: 1.6)
                    .foregroundStyle(palette.sub)
            }
        }
    }
}

// MARK: - Household setup

struct HouseholdSetupView: View {
    let session: SessionStore
    @Environment(\.palette) private var palette

    private enum Mode { case pick, create, join }
    @State private var mode: Mode = .pick
    @State private var householdName = ""
    @State private var displayName = ""
    @State private var inviteCode = ""
    @State private var errorText: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepper(step: 1, label: "HOUSEHOLD")
                .padding(.top, 24)

            Text("ALMOST THERE")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 18)

            Text(mode == .join ? "Join your\nhousehold" : "Set up your\nhousehold")
                .font(EvenFont.serif(32, .medium))
                .foregroundStyle(palette.ink)
                .padding(.top, 10)

            switch mode {
            case .pick: pickButtons
            case .create: createForm
            case .join: joinForm
            }

            Spacer()

            Button {
                Task { await session.signOut() }
            } label: {
                Text("SIGN OUT")
                    .capsLabel(9, tracking: 1.4)
                    .foregroundStyle(palette.sub)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
    }

    private var pickButtons: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Start our household") { mode = .create }
                .accessibilityIdentifier("mode-create")
            GhostButton(title: "I have an invite code") { mode = .join }
                .accessibilityIdentifier("mode-join")
        }
        .padding(.top, 40)
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            UnderlineField(placeholder: "Household name — e.g. Prinsengracht 12", text: $householdName, id: "household-name")
            UnderlineField(placeholder: "Your name — what your partner calls you", text: $displayName, id: "display-name-create")
            errorLine
            PrimaryButton(title: working ? "Creating…" : "Create — get the invite code",
                          enabled: ready(householdName) && ready(displayName) && !working) {
                submit {
                    try await session.createHousehold(
                        name: householdName.trimmingCharacters(in: .whitespaces),
                        displayName: displayName.trimmingCharacters(in: .whitespaces))
                }
            }
            .accessibilityIdentifier("create-household")
            Button { mode = .join } label: {
                Text("HAVE A CODE INSTEAD?").capsLabel(9, tracking: 1.2).foregroundStyle(palette.sub)
            }
        }
        .padding(.top, 34)
    }

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            UnderlineField(placeholder: "Invite code — 6 characters", text: $inviteCode, id: "invite-code")
            UnderlineField(placeholder: "Your name — what your partner calls you", text: $displayName, id: "display-name-join")
            errorLine
            PrimaryButton(title: working ? "Joining…" : "Join the household",
                          enabled: inviteCode.trimmingCharacters(in: .whitespaces).count >= 6
                                   && ready(displayName) && !working) {
                submit {
                    try await session.joinHousehold(
                        inviteCode: inviteCode.trimmingCharacters(in: .whitespaces).uppercased(),
                        displayName: displayName.trimmingCharacters(in: .whitespaces))
                }
            }
            .accessibilityIdentifier("join-household")
            Button { mode = .create } label: {
                Text("START FRESH INSTEAD?").capsLabel(9, tracking: 1.2).foregroundStyle(palette.sub)
            }
        }
        .padding(.top, 34)
    }

    @ViewBuilder
    private var errorLine: some View {
        if let errorText {
            Text(errorText)
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.clay)
        }
    }

    private func ready(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit(_ action: @escaping () async throws -> Void) {
        working = true
        errorText = nil
        Task {
            do {
                try await action()
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? "That didn't work."
            }
            working = false
        }
    }
}

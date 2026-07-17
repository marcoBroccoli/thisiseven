import SwiftUI
import EvenCore
import AuthenticationServices
import CryptoKit

// Onboarding per docs/design/even-onboarding.dc.html: welcome/sign-in,
// how-it-works pager, path choice, create, join (+ error state).

/// "--skip-google-prompt" suppresses every onboarding extra (pager, invite
/// reveal, google, notifications) so the UI test suites drive a bare flow.
var skipOnboardingExtras: Bool {
    ProcessInfo.processInfo.arguments.contains("--skip-google-prompt")
}

struct OnboardingFlow: View {
    let session: SessionStore
    @Environment(\.palette) private var palette
    @AppStorage("even-seen-howitworks") private var seenHowItWorks = false

    var body: some View {
        switch session.phase {
        case .needsHousehold:
            if !seenHowItWorks && !skipOnboardingExtras {
                HowItWorksPager { seenHowItWorks = true }
            } else {
                HouseholdSetupView(session: session)
            }
        default:
            WelcomeView(session: session)
        }
    }
}

// MARK: - 02 · Welcome / sign-in

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
                .frame(width: 58, height: 58)
                .offset(y: glyphBobbing ? -3 : 0)
                .animation(glyphBobbing
                           ? .easeInOut(duration: 2).repeatForever(autoreverses: true)
                           : .default,
                           value: glyphBobbing)

            Text("Even")
                .font(EvenFont.serif(46, .semibold, italic: true))
                .foregroundStyle(palette.ink)
                .padding(.top, 14)
                .landing(showTitle)

            Text("One house, two people, kept even.")
                .font(EvenFont.serif(17))
                .foregroundStyle(Color(hex: 0x6E6353))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 12)
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
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

                Text("Only the two of you ever see what's inside. No ads, no tracking.")
                    .font(EvenFont.serif(12.5, italic: true))
                    .foregroundStyle(palette.sub)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
            }
            .landing(showOptions)
        }
        .padding(.horizontal, 28)
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
            // Plain field on purpose: a SecureField triggers the iOS
            // save-password sheet, which blocks the UI test suites. This
            // sheet is DEBUG-only tooling; visibility is fine.
            TextField("password", text: $password)
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

extension View {
    /// The design's fadeUp: rise 8pt and appear.
    func landing(_ shown: Bool) -> some View {
        self.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
    }
}

// MARK: - 03 · How it works (3-page pager)

struct HowItWorksPager: View {
    let done: () -> Void
    @Environment(\.palette) private var palette
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HOW EVEN WORKS")
                    .capsLabel(9.5, tracking: 1.8)
                    .foregroundStyle(palette.sub)
                Spacer()
                Button(action: done) {
                    Text("SKIP")
                        .capsLabel(10, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .underline()
                }
            }
            .padding(.top, 24)

            TabView(selection: $page) {
                howPage(0,
                        title: "Work you can weigh.",
                        body: "Every finished task drops a pebble in your pan — heavier chores, heavier pebbles. The beam shows the week's balance at a glance, so nobody has to keep score out loud.") {
                    HowScaleIllustration()
                }
                howPage(1,
                        title: "Drafts, not demands.",
                        body: "Bills and appointments in your Gmail become drafts in a shared inbox. A draft turns into a task or calendar event only after your partner has looked at it and approved.") {
                    HowDraftIllustration()
                }
                howPage(2,
                        title: "Sunday, pour the pans.",
                        body: "Once a week, ten minutes together: look at the balance honestly, say one kind thing each, trade what isn't working. Then the pans empty and Monday starts level.") {
                    HowResetIllustration()
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? AnyShapeStyle(palette.ink)
                                        : AnyShapeStyle(palette.ink.opacity(0.2)))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            .padding(.vertical, 16)

            PrimaryButton(title: page == 2 ? "Get started" : "Next") {
                if page == 2 {
                    done()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 28)
    }

    private func howPage<I: View>(_ index: Int, title: String, body: String,
                                  @ViewBuilder illustration: () -> I) -> some View {
        VStack(spacing: 0) {
            Spacer()
            illustration()
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(EvenFont.serif(30, .medium))
                    .foregroundStyle(palette.ink)
                Text(body)
                    .font(EvenFont.serif(15.5))
                    .foregroundStyle(Color(hex: 0x6E6353))
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        }
        .tag(index)
    }
}

// MARK: - 04 · Path choice + 05 create + 07 join

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
            switch mode {
            case .pick: pathChoice
            case .create: createForm
            case .join: joinForm
            }
        }
        .padding(.horizontal, 28)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode == .pick)
    }

    // 04 — path choice

    private var pathChoice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SIGNED IN")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 46)

            Text("Set up your\nhousehold.")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 10)

            Text("An Even household holds exactly two people.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            VStack(spacing: 12) {
                pathCard(title: "Start a new household",
                         sub: "YOU'LL GET A CODE TO HAND YOUR PARTNER",
                         raised: true) { mode = .create }
                    .accessibilityLabel("Start our household")
                    .accessibilityIdentifier("mode-create")
                pathCard(title: "Join with a code",
                         sub: "YOUR PARTNER GAVE YOU SIX CHARACTERS",
                         raised: false) { mode = .join }
                    .accessibilityLabel("I have an invite code")
                    .accessibilityIdentifier("mode-join")
            }
            .padding(.top, 28)

            Spacer()

            HStack {
                Spacer()
                Button {
                    Task { await session.signOut() }
                } label: {
                    Text("SIGN OUT")
                        .capsLabel(10, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .underline()
                }
                Spacer()
            }
            .padding(.bottom, 24)
        }
    }

    private func pathCard(title: String, sub: String, raised: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(EvenFont.serif(19, .medium))
                        .foregroundStyle(palette.ink)
                    Text(sub)
                        .capsLabel(11, tracking: 0.3)
                        .foregroundStyle(palette.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.ink)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(raised ? palette.card : .clear))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }

    // 05 — create household

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton { mode = .pick }

            Text("Name your\nhousehold.")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 18)

            Text("Both of these can change later.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            fieldBlock(label: "HOUSEHOLD NAME") {
                UnderlineField(placeholder: "The Attic", text: $householdName,
                               serifSize: 22, id: "household-name")
            }
            .padding(.top, 34)

            fieldBlock(label: "YOUR NAME") {
                UnderlineField(placeholder: "Ada", text: $displayName,
                               serifSize: 22, id: "display-name-create")
            }
            .padding(.top, 26)

            Text("This is the name on your pan of the scale — what your partner sees on tasks and pebbles.")
                .font(EvenFont.serif(12.5, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 10)

            errorLine

            Spacer()

            PrimaryButton(title: working ? "Creating…" : "Create household",
                          enabled: ready(householdName) && ready(displayName) && !working) {
                submit {
                    try await session.createHousehold(
                        name: householdName.trimmingCharacters(in: .whitespaces),
                        displayName: displayName.trimmingCharacters(in: .whitespaces))
                }
            }
            .accessibilityLabel("Create — get the invite code")
            .accessibilityIdentifier("create-household")
            .padding(.bottom, 30)
        }
    }

    // 07 — join household (+ error state)

    private var joinForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton { mode = .pick; errorText = nil }

            Text("Enter the\ncode.")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 18)

            Text("Six characters, from your partner.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            CodeEntryBoxes(code: $inviteCode, isError: errorText != nil)
                .padding(.top, 30)

            if let errorText {
                Text(errorText)
                    .font(EvenFont.serif(13.5, italic: true))
                    .foregroundStyle(palette.clay)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }

            fieldBlock(label: "YOUR NAME") {
                UnderlineField(placeholder: "Umut", text: $displayName,
                               serifSize: 22, id: "display-name-join")
            }
            .padding(.top, errorText == nil ? 30 : 24)

            Spacer()

            if errorText != nil {
                GhostButton(title: "Try again") {
                    errorText = nil
                    inviteCode = ""
                }
                .padding(.bottom, 30)
            } else {
                PrimaryButton(title: working ? "Joining…" : "Join household",
                              enabled: inviteCode.trimmingCharacters(in: .whitespaces).count >= 6
                                       && ready(displayName) && !working) {
                    submit {
                        try await session.joinHousehold(
                            inviteCode: inviteCode.trimmingCharacters(in: .whitespaces).uppercased(),
                            displayName: displayName.trimmingCharacters(in: .whitespaces))
                    }
                }
                .accessibilityLabel("Join the household")
                .accessibilityIdentifier("join-household")
                .padding(.bottom, 30)
            }
        }
    }

    // shared bits

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("← BACK")
                .capsLabel(10, tracking: 1.2)
                .foregroundStyle(palette.sub)
        }
        .padding(.top, 24)
    }

    private func fieldBlock<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .capsLabel(9.5, tracking: 1.8)
                .foregroundStyle(palette.sub)
            content()
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if mode == .create, let errorText {
            Text(errorText)
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.clay)
                .padding(.top, 12)
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
                if mode == .join {
                    errorText = "That code doesn't match an open household — or it's already been used. Check it with your partner; codes retire once both of you are in."
                } else {
                    errorText = (error as? LocalizedError)?.errorDescription ?? "That didn't work."
                }
            }
            working = false
        }
    }
}

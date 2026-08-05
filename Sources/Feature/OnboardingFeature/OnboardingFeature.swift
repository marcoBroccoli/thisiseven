import AuthClient
import AuthenticationServices
import ComposableArchitecture
import CryptoKit
import Design
import EvenCore
import Security
import SwiftUI

@Reducer
public struct OnboardingFeature {
    @ObservableState
    public struct State: Equatable {
        public var step: Step = .welcome
        public var howItWorksPage = 1
        public var error: String?
        public var working = false
        public init(step: Step = .welcome) {
            self.step = step
        }
    }

    public enum Step: Equatable, Sendable {
        case welcome
        case howItWorks
    }

    public enum Action {
        case appleCompleted(identityToken: String, rawNonce: String?)
        case debugEmailSignIn(email: String, password: String)
        case debugEmailSignUp(email: String, password: String)
        case signInSucceeded(AuthBootstrapResult)
        case signInFailed(String)
        case nextHowItWorks
        case skipHowItWorks
        case delegate(Delegate)
        @CasePathable
        public enum Delegate: Equatable {
            case needsHousehold
            case alreadyReady
        }
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .appleCompleted(token, nonce):
                state.working = true
                state.error = nil
                return .run { [authClient] send in
                    do {
                        let result = try await authClient.signInWithApple(token, nonce)
                        await send(.signInSucceeded(result))
                    } catch {
                        await send(.signInFailed(String(describing: error)))
                    }
                }

            case let .debugEmailSignIn(email, password):
                state.working = true
                state.error = nil
                return .run { [authClient] send in
                    do {
                        let result = try await authClient.signInEmail(email, password)
                        await send(.signInSucceeded(result))
                    } catch {
                        await send(.signInFailed(String(describing: error)))
                    }
                }

            case let .debugEmailSignUp(email, password):
                state.working = true
                state.error = nil
                return .run { [authClient] send in
                    do {
                        let result = try await authClient.signUpEmail(email, password)
                        await send(.signInSucceeded(result))
                    } catch {
                        await send(.signInFailed(String(describing: error)))
                    }
                }

            case let .signInSucceeded(result):
                state.working = false
                switch result {
                case .ready:
                    return .send(.delegate(.alreadyReady))
                case .needsHousehold, .signedOut:
                    state.step = .howItWorks
                    state.howItWorksPage = 1
                    return .none
                }

            case let .signInFailed(message):
                state.working = false
                state.error = message
                return .none

            case .nextHowItWorks:
                if state.howItWorksPage < 3 {
                    state.howItWorksPage += 1
                    return .none
                }
                return .send(.delegate(.needsHousehold))

            case .skipHowItWorks:
                return .send(.delegate(.needsHousehold))

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - View

public struct OnboardingFeatureView: View {
    @Bindable public var store: StoreOf<OnboardingFeature>
    @State private var rawNonce = ""
    @State private var showDebugAuth = false

    public init(store: StoreOf<OnboardingFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.step {
            case .welcome:
                welcome
            case .howItWorks:
                howItWorks
            }
        }
        .background(EvenTokens.paperRaised.ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            EvenScaleGlyph()
                .stroke(EvenTokens.espresso, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 58, height: 58)
            Text("Even")
                .font(.system(size: 46, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
                .padding(.top, 14)
            Text("One house, two people, kept even.")
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(Color(hex: 0x6E6353))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 12)
            Spacer()

            if let error = store.error {
                Text(error)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.terracotta)
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(store.working)

            #if DEBUG
                Button("DEV — EMAIL SIGN-IN") { showDebugAuth = true }
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(EvenTokens.stone)
                    .padding(.top, 14)
                    .accessibilityIdentifier("dev-email-signin")
                    .sheet(isPresented: $showDebugAuth) {
                        DebugEmailSheet(
                            onSignIn: { email, password in
                                store.send(.debugEmailSignIn(email: email, password: password))
                            },
                            onSignUp: { email, password in
                                store.send(.debugEmailSignUp(email: email, password: password))
                            }
                        )
                    }
            #endif

            Text("Only the two of you ever see what's inside. No ads, no tracking.")
                .font(.system(size: 12.5, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.stone)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
    }

    private var howItWorks: some View {
        let page = store.howItWorksPage
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HOW EVEN WORKS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(EvenTokens.stone)
                Spacer()
                Button("SKIP") { store.send(.skipHowItWorks) }
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(EvenTokens.stone)
            }
            .padding(.top, 64)

            Spacer()
            howItWorksArt(page)
            Spacer()

            Text(howItWorksCopy(page).title)
                .font(.system(size: 30, weight: .medium, design: .serif))
                .foregroundStyle(EvenTokens.espresso)
            Text(howItWorksCopy(page).body)
                .font(.system(size: 15.5))
                .foregroundStyle(Color(hex: 0x6E6353))
                .padding(.top, 10)
                .frame(minHeight: 110, alignment: .top)

            HStack(spacing: 6) {
                ForEach(1 ... 3, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? EvenTokens.espresso : EvenTokens.espresso.opacity(0.2))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            EvenPrimaryButton(page < 3 ? "Next" : "Get started") {
                store.send(.nextHowItWorks)
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func howItWorksArt(_ page: Int) -> some View {
        switch page {
        case 1:
            EvenScaleGlyph()
                .stroke(EvenTokens.espresso, lineWidth: 2)
                .frame(width: 200, height: 120)
                .frame(maxWidth: .infinity)
        case 2:
            VStack(spacing: 10) {
                Label("GMAIL · READ-ONLY", systemImage: "envelope")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                RoundedRectangle(cornerRadius: 13)
                    .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
                    .background(EvenTokens.paperCard.clipShape(RoundedRectangle(cornerRadius: 13)))
                    .frame(height: 72)
                    .overlay {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CITY OF UTRECHT · DRAFT")
                                .font(.system(size: 9, weight: .bold))
                            Text("Water bill — €84, due Friday")
                                .font(.system(size: 14.5, design: .serif))
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 40)
            }
        default:
            VStack(spacing: 8) {
                Text("SUNDAY · 6 PM")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(2.8)
                    .foregroundStyle(EvenTokens.stone)
                Capsule().fill(EvenTokens.espresso).frame(width: 180, height: 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func howItWorksCopy(_ page: Int) -> (title: String, body: String) {
        switch page {
        case 1:
            ("Work you can weigh.",
             "Every finished task drops a pebble in your pan — heavier chores, heavier pebbles. The beam shows the week's balance at a glance.")
        case 2:
            ("Drafts, not demands.",
             "Bills and appointments in your Gmail become drafts in a shared inbox. A draft turns into a task only after your partner approves.")
        default:
            ("Sunday, pour the pans.",
             "Once a week, ten minutes together: look at the balance honestly, say one kind thing each, trade what isn't working.")
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            store.send(.signInFailed(error.localizedDescription))
        case let .success(auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken,
                  let token = String(data: data, encoding: .utf8)
            else {
                store.send(.signInFailed("Apple Sign In returned no identity token."))
                return
            }
            store.send(.appleCompleted(identityToken: token, rawNonce: rawNonce))
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#if DEBUG
    private struct DebugEmailSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var email = "umur@thisiseven.app"
        @State private var password = ""
        let onSignIn: (String, String) -> Void
        let onSignUp: (String, String) -> Void

        var body: some View {
            NavigationStack {
                Form {
                    TextField("Email", text: $email)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                        .accessibilityIdentifier("auth-email")
                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("auth-password")
                }
                .navigationTitle("Dev sign-in")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button("Sign up") {
                            onSignUp(email, password)
                            dismiss()
                        }
                        .accessibilityIdentifier("auth-signup")
                        Button("Sign in") {
                            onSignIn(email, password)
                            dismiss()
                        }
                        .accessibilityIdentifier("auth-signin")
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
#endif

#Preview("Onboarding · welcome") {
    OnboardingFeatureView(store: OnboardingPreviewSupport.welcome())
}

#Preview("Onboarding · how it works 1") {
    OnboardingFeatureView(store: OnboardingPreviewSupport.howItWorks(page: 1))
}

#Preview("Onboarding · how it works 3") {
    OnboardingFeatureView(store: OnboardingPreviewSupport.howItWorks(page: 3))
}

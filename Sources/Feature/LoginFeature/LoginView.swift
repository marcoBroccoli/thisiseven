#if os(iOS)
    import AuthClient
    import AuthenticationServices
    import ComposableArchitecture
    import CryptoKit
    import Design
    import EvenCore
    import Foundation
    import Security
    import SwiftUI

    @ViewAction(for: LoginReducer.self)
    public struct LoginView: View {
        @Bindable public var store: StoreOf<LoginReducer>
        @State private var rawNonce = ""
        @State private var showDebugAuth = false
        @State private var glyphProgress: CGFloat = 0
        @State private var showTitle = false
        @State private var layoutExpanded = false

        public init(store: StoreOf<LoginReducer>) {
            self.store = store
        }

        private enum ViewConfig {
            static let glyph: CGFloat = 58
            static let horizontalPadding: CGFloat = 28
        }

        private enum AnimationConfig {
            static let glyphDraw = Animation.easeInOut(duration: 0.65)
            static let titleSlide = Animation.easeOut(duration: 0.5)
            static let expand = Animation.spring(response: 0.55, dampingFraction: 0.88)
            static let titleDelay: Double = 0.45
            static let expandDelay: Double = 1.05
        }

        public var body: some View {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                brandPair

                if layoutExpanded {
                    Text("One house, two people, kept even.")
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(Color(hex: 0x6E6353))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 250)
                        .padding(.top, 12)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }

                Spacer(minLength: 0)

                if layoutExpanded {
                    footer
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            }
            .padding(.horizontal, ViewConfig.horizontalPadding)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .evenPaperBackground()
            .animation(EvenMotion.reveal, value: store.error)
            .animation(EvenMotion.reveal, value: store.working)
            .onAppear { playEntrance() }
        }

        private var brandPair: some View {
            VStack(spacing: 0) {
                EvenDrawnScaleGlyph(progress: glyphProgress, side: ViewConfig.glyph)
                Text("Even")
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(EvenTokens.espresso)
                    .padding(.top, 14)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 14)
            }
        }

        private var footer: some View {
            VStack(spacing: 0) {
                if let error = store.error {
                    Text(error)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(EvenTokens.terracotta)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                        .transition(EvenMotion.fadeUp)
                }

                signInControl
                    .disabled(store.working)
                    .opacity(store.working ? 0.55 : 1)

                #if DEBUG
                    if !Self.isRunningForPreviews {
                        Button("DEV — EMAIL SIGN-IN") { showDebugAuth = true }
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(EvenTokens.stone)
                            .padding(.top, 14)
                            .accessibilityIdentifier("dev-email-signin")
                            .sheet(isPresented: $showDebugAuth) {
                                DebugEmailSheet(
                                    onSignIn: { email, password in
                                        send(.debugEmailSignIn(email: email, password: password))
                                    },
                                    onSignUp: { email, password in
                                        send(.debugEmailSignUp(email: email, password: password))
                                    }
                                )
                            }
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
        }

        private func playEntrance() {
            glyphProgress = 0
            showTitle = false
            layoutExpanded = false
            withAnimation(AnimationConfig.glyphDraw) { glyphProgress = 1 }
            withAnimation(AnimationConfig.titleSlide.delay(AnimationConfig.titleDelay)) { showTitle = true }
            withAnimation(AnimationConfig.expand.delay(AnimationConfig.expandDelay)) { layoutExpanded = true }
        }

        @ViewBuilder
        private var signInControl: some View {
            if Self.isRunningForPreviews {
                Button {
                    send(.appleCompleted(
                        identityToken: "preview-apple-identity-token",
                        rawNonce: "preview-nonce"
                    ))
                } label: {
                    EvenAppleSignInChrome()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sign-in-with-apple")
            } else {
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
            }
        }

        private static var isRunningForPreviews: Bool {
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        }

        private func handleApple(_ result: Result<ASAuthorization, Error>) {
            switch result {
            case let .failure(error):
                send(.authorizationFailed(error.localizedDescription))
            case let .success(auth):
                guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                      let data = cred.identityToken,
                      let token = String(data: data, encoding: .utf8)
                else {
                    send(.authorizationFailed("Apple Sign In returned no identity token."))
                    return
                }
                send(.appleCompleted(identityToken: token, rawNonce: rawNonce))
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
            SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
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
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("auth-email")
                        SecureField("Password", text: $password)
                            .accessibilityIdentifier("auth-password")
                    }
                    .navigationTitle("Dev sign-in")
                    .navigationBarTitleDisplayMode(.inline)
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

    #Preview("Login · flow") {
        LoginView(store: LoginPreviewSupport.flow())
    }

    #Preview("Login · error") {
        LoginView(store: LoginPreviewSupport.error())
    }
#endif

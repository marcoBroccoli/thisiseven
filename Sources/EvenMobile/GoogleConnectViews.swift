import SwiftUI
import EvenCore
import AuthenticationServices

// In-app Google connect — the consent runs in ASWebAuthenticationSession,
// the token exchange happens in evend, per household, concurrent-safe.

@MainActor
final class GoogleConnector: NSObject, ObservableObject {
    @Published var working = false
    @Published var errorText: String?

    private var session: ASWebAuthenticationSession?

    /// Runs one consent attempt and completes the backend exchange.
    func connect(model: AppModel) async -> Bool {
        guard GoogleConnectConfig.isEnabled else { return false }
        errorText = nil
        working = true
        defer { working = false }

        let attempt = GoogleConnectAttempt()
        do {
            let callback = try await authenticate(url: attempt.authorizationURL,
                                                  scheme: GoogleConnectConfig.redirectScheme)
            guard let code = attempt.code(from: callback) else {
                errorText = "Google didn't hand back a usable code."
                return false
            }
            let status = try await model.api.googleConnect(code: code,
                                                           codeVerifier: attempt.codeVerifier)
            model.googleStatus = status
            model.stamp("GMAIL CONNECTED ✓")
            Task { await model.syncGmail() }
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
                ?? "Connecting Google didn't work. Try again."
            return false
        }
    }

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url,
                                                     callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? URLError(.userCancelledAuthentication))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }
}

extension GoogleConnector: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        return MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
        #else
        return ASPresentationAnchor()
        #endif
    }
}

// MARK: - Onboarding step (full-screen, once, skippable)

/// Shown once after the household exists, before daily use — the design's
/// voice, two choices, never blocks.
struct GoogleConnectPrompt: View {
    @Bindable var model: AppModel
    let done: () -> Void
    @Environment(\.palette) private var palette
    @StateObject private var connector = GoogleConnector()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepper(step: 2, label: "GOOGLE")
                .padding(.top, 24)

            Text("ONE LAST THING — OPTIONAL")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 18)

            Text("Let Even read\nthe mail pile")
                .font(EvenFont.serif(32, .medium))
                .foregroundStyle(palette.ink)
                .padding(.top, 10)

            Text("Even reads bills and appointments from your Gmail and turns them into drafts for the approval inbox. When you approve one, it lands on your calendar with a reminder.")
                .font(EvenFont.serif(15))
                .foregroundStyle(palette.ink)
                .lineSpacing(4)
                .padding(.top, 14)

            Text("Read-only on mail. Nothing is shared, nothing is sent. It stays on your own server.")
                .font(EvenFont.serif(13, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            if let errorText = connector.errorText {
                Text(errorText)
                    .font(EvenFont.serif(13, italic: true))
                    .foregroundStyle(palette.clay)
                    .padding(.top, 12)
            }

            Spacer()

            PrimaryButton(title: connector.working ? "Connecting…" : "Connect Google",
                          enabled: !connector.working) {
                Task {
                    if await connector.connect(model: model) { done() }
                }
            }
            GhostButton(title: "Later — it also lives in the Inbox") { done() }
                .padding(.top, 10)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .background(palette.bg.ignoresSafeArea())
    }
}

// MARK: - Inbox card (quiet, whenever not connected)

struct GoogleConnectCard: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @StateObject private var connector = GoogleConnector()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GMAIL — NOT CONNECTED")
                .capsLabel(9, tracking: 1.5)
                .foregroundStyle(palette.sub)
            Text("Connect Google and the bills find their own way here.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.ink)
            if let errorText = connector.errorText {
                Text(errorText)
                    .font(EvenFont.serif(12.5, italic: true))
                    .foregroundStyle(palette.clay)
            }
            Button {
                Task { _ = await connector.connect(model: model) }
            } label: {
                Text(connector.working ? "CONNECTING…" : "CONNECT GOOGLE")
                    .capsLabel(10, tracking: 1.2)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(Capsule().stroke(palette.ink, lineWidth: 1.5))
            }
            .buttonStyle(PressScaleStyle(scale: 0.96))
            .disabled(connector.working)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

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

/// 08 · Connect Google — the design's optional step: three icon rows, a
/// Google-marked button, skippable.
struct GoogleConnectPrompt: View {
    @Bindable var model: AppModel
    let done: () -> Void
    @Environment(\.palette) private var palette
    @StateObject private var connector = GoogleConnector()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OPTIONAL · YOU CAN DO THIS ANY TIME")
                .capsLabel(10, tracking: 1.8)
                .foregroundStyle(palette.sub)
                .padding(.top, 46)

            Text("Let Gmail do\nthe noticing.")
                .font(EvenFont.serif(34, .medium))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 10)

            Text("Read-only. Even never sends, moves, or deletes mail.")
                .font(EvenFont.serif(14, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 12)

            VStack(spacing: 18) {
                promiseRow(icon: "magnifyingglass",
                           title: "It scans for bills and appointments",
                           body: "Utility bills, dentist reminders, school emails — spotted so neither of you has to be the one who notices.")
                promiseRow(icon: "tray",
                           title: "Everything lands as a draft",
                           body: "Into the shared Approval Inbox. Your partner approves before anything becomes a task.")
                promiseRow(icon: "calendar",
                           title: "Approved drafts hit the calendar",
                           body: "One event, one reminder. Never without a yes from one of you.")
            }
            .padding(.top, 30)

            if let errorText = connector.errorText {
                Text(errorText)
                    .font(EvenFont.serif(13, italic: true))
                    .foregroundStyle(palette.clay)
                    .padding(.top, 12)
            }

            Spacer()

            Button {
                Task {
                    if await connector.connect(model: model) { done() }
                }
            } label: {
                HStack(spacing: 10) {
                    GoogleGMark()
                        .frame(width: 18, height: 18)
                    Text(connector.working ? "Connecting…" : "Connect Google")
                        .font(EvenFont.sans(15.5, .semibold))
                }
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line, lineWidth: 1.5))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(connector.working)

            HStack {
                Spacer()
                Button(action: done) {
                    Text("SKIP FOR NOW")
                        .capsLabel(10, tracking: 1.4)
                        .foregroundStyle(palette.sub)
                        .underline()
                }
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 28)
        .background(palette.bg.ignoresSafeArea())
    }

    private func promiseRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(palette.faint))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(EvenFont.serif(16, .medium))
                    .foregroundStyle(palette.ink)
                Text(body)
                    .font(EvenFont.serif(13.5))
                    .foregroundStyle(Color(hex: 0x6E6353))
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The four-color Google G, drawn as trimmed arcs — close enough at 18pt.
struct GoogleGMark: View {
    var body: some View {
        ZStack {
            arc(0.03, 0.31, Color(hex: 0xEA4335))   // red — top left
            arc(0.56, 0.81, Color(hex: 0xFBBC05))   // yellow — bottom left
            arc(0.31, 0.56, Color(hex: 0x34A853))   // green — bottom right
            arc(0.81, 0.95, Color(hex: 0x4285F4))   // blue — top right
            Rectangle()
                .fill(Color(hex: 0x4285F4))
                .frame(width: 8, height: 3.2)
                .offset(x: 3.2, y: 0)
        }
        .frame(width: 18, height: 18)
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ color: Color) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: 3.2))
            .rotationEffect(.degrees(180))
            .padding(1.6)
    }
}

// MARK: - Source connection card

struct GoogleConnectCard: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @StateObject private var connector = GoogleConnector()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOOGLE — NOT CONNECTED")
                .capsLabel(9, tracking: 1.5)
                .foregroundStyle(palette.sub)
            Text("Connect Gmail and Calendar for shared household todos.")
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

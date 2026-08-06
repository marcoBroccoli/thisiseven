import AuthenticationServices
import Dependencies
import EvenCore
import Foundation
import GoogleClient
#if canImport(UIKit)
    import UIKit
#endif

extension GoogleClient: DependencyKey {
    public static let liveValue = GoogleClient(
        status: {
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.googleStatus()
        },
        startSync: {
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.googleSync()
        },
        connect: {
            guard GoogleConnectConfig.isEnabled else {
                throw GoogleClientError.unimplemented
            }
            let attempt = GoogleConnectAttempt()
            let callback = try await GoogleOAuthPresenter.shared.authenticate(
                url: attempt.authorizationURL,
                scheme: GoogleConnectConfig.redirectScheme
            )
            guard let code = attempt.code(from: callback) else {
                throw GoogleClientError.unimplemented
            }
            let api = await MainActor.run { SharedSession.store.api }
            _ = try await api.googleConnect(code: code, codeVerifier: attempt.codeVerifier)
        },
        disconnect: {
            let api = await MainActor.run { SharedSession.store.api }
            try await api.googleDisconnect()
        }
    )
}

@MainActor
final class GoogleOAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleOAuthPresenter()
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
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

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
            MainActor.assumeIsolated {
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first ?? ASPresentationAnchor()
            }
        #else
            ASPresentationAnchor()
        #endif
    }
}

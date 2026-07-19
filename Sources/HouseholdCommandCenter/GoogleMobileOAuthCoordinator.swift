#if os(iOS)
import Foundation
import GoogleSignIn
import HouseholdCore
import UIKit

struct GoogleMobileIdentity: Equatable {
    var accountHint: String
    var grantedScopes: [String]
}

enum GoogleMobileOAuthError: Error, LocalizedError {
    case missingPresentationController
    case missingAccessToken
    case missingURLScheme(String)

    var errorDescription: String? {
        switch self {
        case .missingPresentationController:
            "Google sign-in could not find the active app window. Try again from the foreground."
        case .missingAccessToken:
            "Google sign-in completed without an access token."
        case .missingURLScheme(let scheme):
            "This build is missing the Google iOS URL scheme '\(scheme)'. Add it to MobileApp/Config/Google.xcconfig and rebuild."
        }
    }
}

@MainActor
final class GoogleMobileOAuthCoordinator {
    private static let scopes = [
        GoogleOAuthScope.gmailReadonly.rawValue,
        GoogleOAuthScope.gmailCompose.rawValue,
        GoogleOAuthScope.calendarEvents.rawValue,
        GoogleOAuthScope.openid.rawValue,
        GoogleOAuthScope.email.rawValue,
        GoogleOAuthScope.profile.rawValue
    ]

    func connect(clientID: String, accountHint: String) async throws -> GoogleMobileIdentity {
        guard let requiredScheme = Self.callbackScheme(for: clientID), Self.hasRegisteredScheme(requiredScheme) else {
            throw GoogleMobileOAuthError.missingURLScheme(Self.callbackScheme(for: clientID) ?? "com.googleusercontent.apps.<client-id>")
        }
        guard let controller = Self.presentationController() else {
            throw GoogleMobileOAuthError.missingPresentationController
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await signIn(
            presenting: controller,
            accountHint: accountHint,
            additionalScopes: Self.scopes
        )
        return Self.identity(from: result.user, fallbackAccountHint: accountHint)
    }

    func restorePreviousSignIn() async throws -> GoogleMobileIdentity? {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
        let user = try await restore()
        return Self.identity(from: user, fallbackAccountHint: "Google account")
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    static var hasCurrentUser: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    static func handle(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func signIn(
        presenting controller: UIViewController,
        accountHint: String,
        additionalScopes: [String]
    ) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: controller,
                hint: accountHint,
                additionalScopes: additionalScopes
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: GoogleMobileOAuthError.missingAccessToken)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func restore() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user else {
                    continuation.resume(throwing: GoogleMobileOAuthError.missingAccessToken)
                    return
                }
                continuation.resume(returning: user)
            }
        }
    }

    private static func identity(from user: GIDGoogleUser, fallbackAccountHint: String) -> GoogleMobileIdentity {
        GoogleMobileIdentity(
            accountHint: user.profile?.email ?? fallbackAccountHint,
            grantedScopes: user.grantedScopes ?? []
        )
    }

    private static func callbackScheme(for clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let identifier = clientID.dropLast(suffix.count)
        guard !identifier.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(identifier)"
    }

    private static func hasRegisteredScheme(_ requiredScheme: String) -> Bool {
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return urlTypes.contains { type in
            let schemes = type["CFBundleURLSchemes"] as? [String] ?? []
            return schemes.contains { $0.caseInsensitiveCompare(requiredScheme) == .orderedSame }
        }
    }

    private static func presentationController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let root = windowScene?.keyWindow?.rootViewController
        return visibleViewController(from: root)
    }

    private static func visibleViewController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController {
            return visibleViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return visibleViewController(from: navigation.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return visibleViewController(from: tab.selectedViewController)
        }
        return controller
    }
}

final class GoogleMobileAccessTokenProvider: GoogleAccessTokenProvider, @unchecked Sendable {
    func accessToken() async throws -> String {
        try await Task { @MainActor in
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                throw GoogleKeychainTokenStoreError.missingStoredTokens
            }

            let refreshedUser = try await user.refreshTokensIfNeeded()
            let token = refreshedUser.accessToken.tokenString
            guard !token.isEmpty else {
                throw GoogleMobileOAuthError.missingAccessToken
            }
            return token
        }.value
    }
}
#endif

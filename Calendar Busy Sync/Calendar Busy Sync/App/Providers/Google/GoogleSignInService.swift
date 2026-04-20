import Foundation
import GoogleSignIn

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GoogleConnectedAccount: Equatable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let grantedScopes: [String]
    let usesCustomOAuthApp: Bool
    let serverAuthCodeAvailable: Bool
}

enum GoogleSignInServiceError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case presenterUnavailable
    case archiveFailure
    case storedAccountCorrupt
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case .presenterUnavailable:
            return "Google Sign-In needs an active app window before it can present the authorization flow."
        case .archiveFailure:
            return "The Google account session could not be saved for later use."
        case .storedAccountCorrupt:
            return "A saved Google account session is corrupt. Remove the account and connect it again."
        case .missingAccessToken:
            return "Google Sign-In did not return an access token for Calendar API calls."
        }
    }
}

@MainActor
enum GoogleSignInService {
    static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    static func restorePreviousSignIn(
        using resolution: GoogleOAuthConfigurationResolution
    ) async throws -> StoredGoogleAccount? {
        guard case let .valid(configuration) = resolution else {
            return nil
        }

        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            return nil
        }

        apply(configuration: configuration)
        let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        return try storedAccount(from: user, usesCustomOAuthApp: configuration.usesCustomApp)
    }

    static func signIn(using resolution: GoogleOAuthConfigurationResolution) async throws -> StoredGoogleAccount {
        try await signIn(using: resolution, hint: nil)
    }

    static func signIn(
        using resolution: GoogleOAuthConfigurationResolution,
        hint: String?
    ) async throws -> StoredGoogleAccount {
        let configuration = try validatedConfiguration(from: resolution)
        let normalizedHint = normalizedHint(hint)
        let hostedDomain = hostedDomain(for: normalizedHint)
        apply(configuration: configuration, hostedDomain: hostedDomain)
        clearSavedSession()

        #if os(iOS)
        let presenter = try presentingViewController()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: normalizedHint,
            additionalScopes: GoogleCalendarScopes.required
        )
        #elseif os(macOS)
        let presenter = try presentingWindow()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: normalizedHint,
            additionalScopes: GoogleCalendarScopes.required
        )
        #endif

        return try storedAccount(
            from: result.user,
            usesCustomOAuthApp: configuration.usesCustomApp,
            serverAuthCodeAvailable: result.serverAuthCode != nil
        )
    }

    static func removeCurrentUserIfMatches(
        accountID: String,
        using resolution: GoogleOAuthConfigurationResolution
    ) {
        guard
            let currentAccount = currentConnectedAccount(using: resolution),
            currentAccount.id == accountID
        else {
            return
        }

        GIDSignIn.sharedInstance.signOut()
    }

    static func clearSavedSession() {
        GIDSignIn.sharedInstance.signOut()
    }

    static func currentConnectedAccount(
        using resolution: GoogleOAuthConfigurationResolution
    ) -> GoogleConnectedAccount? {
        guard
            case let .valid(configuration) = resolution,
            let user = GIDSignIn.sharedInstance.currentUser
        else {
            return nil
        }

        return connectedAccount(
            from: user,
            usesCustomOAuthApp: configuration.usesCustomApp,
            serverAuthCodeAvailable: false
        )
    }

    static func authorizeStoredAccount(_ account: StoredGoogleAccount) async throws -> GoogleAuthorizedAccount {
        let user = try unarchiveUser(from: account.archivedUserData)
        let refreshedUser = try await user.refreshTokensIfNeeded()
        let token = refreshedUser.accessToken.tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GoogleSignInServiceError.missingAccessToken
        }

        let refreshedAccount = try storedAccount(
            from: refreshedUser,
            usesCustomOAuthApp: account.usesCustomOAuthApp
        )
        return GoogleAuthorizedAccount(storedAccount: refreshedAccount, accessToken: token)
    }

    private static func validatedConfiguration(
        from resolution: GoogleOAuthConfigurationResolution
    ) throws -> ResolvedGoogleOAuthConfiguration {
        guard case let .valid(configuration) = resolution else {
            if case let .invalid(message) = resolution {
                throw GoogleSignInServiceError.invalidConfiguration(message)
            }
            fatalError("Unhandled Google OAuth configuration resolution state")
        }

        return configuration
    }

    private static func apply(
        configuration: ResolvedGoogleOAuthConfiguration,
        hostedDomain: String? = nil
    ) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: configuration.clientID,
            serverClientID: configuration.serverClientID,
            hostedDomain: hostedDomain,
            openIDRealm: nil
        )
    }

    private static func storedAccount(
        from user: GIDGoogleUser,
        usesCustomOAuthApp: Bool,
        serverAuthCodeAvailable: Bool = false
    ) throws -> StoredGoogleAccount {
        let connected = connectedAccount(
            from: user,
            usesCustomOAuthApp: usesCustomOAuthApp,
            serverAuthCodeAvailable: serverAuthCodeAvailable
        )
        let archivedUserData = try archive(user: user)

        return StoredGoogleAccount(
            id: connected.id,
            email: connected.email,
            displayName: connected.displayName,
            grantedScopes: connected.grantedScopes,
            usesCustomOAuthApp: connected.usesCustomOAuthApp,
            archivedUserData: archivedUserData
        )
    }

    private static func connectedAccount(
        from user: GIDGoogleUser,
        usesCustomOAuthApp: Bool,
        serverAuthCodeAvailable: Bool
    ) -> GoogleConnectedAccount {
        let email = user.profile?.email ?? "Unknown Google account"
        let displayName = user.profile?.name ?? email
        let userID = user.userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableID = (userID?.isEmpty == false ? userID! : email.lowercased())

        return GoogleConnectedAccount(
            id: stableID,
            email: email,
            displayName: displayName,
            grantedScopes: user.grantedScopes ?? [],
            usesCustomOAuthApp: usesCustomOAuthApp,
            serverAuthCodeAvailable: serverAuthCodeAvailable
        )
    }

    private static func archive(user: GIDGoogleUser) throws -> Data {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: user, requiringSecureCoding: true)
        } catch {
            throw GoogleSignInServiceError.archiveFailure
        }
    }

    private static func unarchiveUser(from data: Data) throws -> GIDGoogleUser {
        do {
            guard
                let user = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: GIDGoogleUser.self,
                    from: data
                )
            else {
                throw GoogleSignInServiceError.storedAccountCorrupt
            }
            return user
        } catch let error as GoogleSignInServiceError {
            throw error
        } catch {
            throw GoogleSignInServiceError.storedAccountCorrupt
        }
    }

    #if os(iOS)
    private static func presentingViewController() throws -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        for scene in scenes {
            if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
                return root.topMostPresentedController
            }
        }

        if let fallback = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.rootViewController != nil })?
            .rootViewController {
            return fallback.topMostPresentedController
        }

        throw GoogleSignInServiceError.presenterUnavailable
    }
    #elseif os(macOS)
    private static func presentingWindow() throws -> NSWindow {
        if let keyWindow = NSApplication.shared.keyWindow {
            return keyWindow
        }

        if let mainWindow = NSApplication.shared.mainWindow {
            return mainWindow
        }

        if let fallback = NSApplication.shared.windows.first {
            return fallback
        }

        throw GoogleSignInServiceError.presenterUnavailable
    }
    #endif

    private static func normalizedHint(_ hint: String?) -> String? {
        let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hostedDomain(for hint: String?) -> String? {
        guard
            let hint,
            let domain = hint.split(separator: "@", maxSplits: 1).last.map(String.init)
        else {
            return nil
        }

        switch domain.lowercased() {
        case "gmail.com", "googlemail.com":
            return nil
        default:
            return domain
        }
    }
}

#if os(iOS)
private extension UIViewController {
    var topMostPresentedController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedController
        }
        return self
    }
}
#endif

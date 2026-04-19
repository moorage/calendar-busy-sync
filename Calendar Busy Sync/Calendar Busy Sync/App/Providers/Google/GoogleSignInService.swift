import Foundation
import GoogleSignIn

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GoogleConnectedAccount: Equatable {
    let email: String
    let displayName: String
    let grantedScopes: [String]
    let usesCustomOAuthApp: Bool
    let serverAuthCodeAvailable: Bool
}

enum GoogleSignInServiceError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case presenterUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case .presenterUnavailable:
            return "Google Sign-In needs an active app window before it can present the authorization flow."
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
    ) async throws -> GoogleConnectedAccount? {
        guard case let .valid(configuration) = resolution else {
            return nil
        }

        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            return nil
        }

        apply(configuration: configuration)
        let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        return connectedAccount(from: user, usesCustomOAuthApp: configuration.usesCustomApp, serverAuthCodeAvailable: false)
    }

    static func signIn(using resolution: GoogleOAuthConfigurationResolution) async throws -> GoogleConnectedAccount {
        let configuration = try validatedConfiguration(from: resolution)
        apply(configuration: configuration)

        #if os(iOS)
        let presenter = try presentingViewController()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: GoogleCalendarScopes.required
        )
        #elseif os(macOS)
        let presenter = try presentingWindow()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: GoogleCalendarScopes.required
        )
        #endif

        return connectedAccount(
            from: result.user,
            usesCustomOAuthApp: configuration.usesCustomApp,
            serverAuthCodeAvailable: result.serverAuthCode != nil
        )
    }

    static func disconnectCurrentUser() async throws {
        guard GIDSignIn.sharedInstance.currentUser != nil else {
            GIDSignIn.sharedInstance.signOut()
            return
        }

        try await GIDSignIn.sharedInstance.disconnect()
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

        return connectedAccount(from: user, usesCustomOAuthApp: configuration.usesCustomApp, serverAuthCodeAvailable: false)
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

    private static func apply(configuration: ResolvedGoogleOAuthConfiguration) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: configuration.clientID,
            serverClientID: configuration.serverClientID
        )
    }

    private static func connectedAccount(
        from user: GIDGoogleUser,
        usesCustomOAuthApp: Bool,
        serverAuthCodeAvailable: Bool
    ) -> GoogleConnectedAccount {
        let email = user.profile?.email ?? "Unknown Google account"
        let displayName = user.profile?.name ?? email

        return GoogleConnectedAccount(
            email: email,
            displayName: displayName,
            grantedScopes: user.grantedScopes ?? [],
            usesCustomOAuthApp: usesCustomOAuthApp,
            serverAuthCodeAvailable: serverAuthCodeAvailable
        )
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

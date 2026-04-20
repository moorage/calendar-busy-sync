import Foundation

#if os(macOS)
import Security
#endif

struct GoogleSignInEnvironment: Equatable {
    let blockingReason: String?

    var allowsInteractiveSignIn: Bool {
        blockingReason == nil
    }

    static func current(bundle: Bundle = .main) -> GoogleSignInEnvironment {
        #if os(macOS)
        return GoogleSignInEnvironment(
            blockingReason: macOSBlockingReason(bundleIdentifier: bundle.bundleIdentifier)
        )
        #else
        return GoogleSignInEnvironment(blockingReason: nil)
        #endif
    }
}

#if os(macOS)
private extension GoogleSignInEnvironment {
    static func macOSBlockingReason(bundleIdentifier: String?) -> String? {
        guard let executableURL = Bundle.main.executableURL else {
            return genericSignedBuildRequirement(bundleIdentifier: bundleIdentifier)
        }

        var code: SecStaticCode?
        let selfStatus = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code)
        guard selfStatus == errSecSuccess, let code else {
            return genericSignedBuildRequirement(bundleIdentifier: bundleIdentifier)
        }

        var information: CFDictionary?
        let signingStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )

        if signingStatus == errSecCSUnsigned {
            return unsignedBuildRequirement(bundleIdentifier: bundleIdentifier)
        }

        guard
            signingStatus == errSecSuccess,
            let payload = information as? [String: Any]
        else {
            return genericSignedBuildRequirement(bundleIdentifier: bundleIdentifier)
        }

        let teamIdentifier = payload[kSecCodeInfoTeamIdentifier as String] as? String
        if teamIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return missingTeamRequirement(bundleIdentifier: bundleIdentifier)
        }

        return nil
    }

    static func unsignedBuildRequirement(bundleIdentifier: String?) -> String {
        signedBuildMessage(
            bundleIdentifier: bundleIdentifier,
            suffix: "The current app launch is unsigned, so Google Sign-In cannot store its session in the macOS keychain."
        )
    }

    static func missingTeamRequirement(bundleIdentifier: String?) -> String {
        signedBuildMessage(
            bundleIdentifier: bundleIdentifier,
            suffix: "The current app launch does not have an Apple team identifier, so the keychain-backed Google session cannot be persisted."
        )
    }

    static func genericSignedBuildRequirement(bundleIdentifier: String?) -> String {
        signedBuildMessage(
            bundleIdentifier: bundleIdentifier,
            suffix: "This app needs a valid Apple development signature and working Xcode account credentials before Google Sign-In can use the macOS keychain."
        )
    }

    static func signedBuildMessage(bundleIdentifier: String?, suffix: String) -> String {
        let identifier = bundleIdentifier ?? "this bundle"
        return "Google Sign-In on macOS requires a signed app build for \(identifier). \(suffix) Run the app from Xcode with Apple Development signing instead of the unsigned harness build."
    }
}
#endif

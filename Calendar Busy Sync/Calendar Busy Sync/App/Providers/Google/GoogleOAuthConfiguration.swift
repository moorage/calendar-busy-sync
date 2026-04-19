import Foundation

struct DefaultGoogleOAuthConfiguration: Equatable {
    let clientID: String
    let reversedClientID: String
    let serverClientID: String?
}

struct ResolvedGoogleOAuthConfiguration: Equatable {
    enum Source: String, Equatable {
        case bundledDefault
        case customOverride
    }

    let source: Source
    let clientID: String
    let reversedClientID: String
    let serverClientID: String?

    var usesCustomApp: Bool {
        source == .customOverride
    }
}

enum GoogleOAuthConfigurationResolution: Equatable {
    case valid(ResolvedGoogleOAuthConfiguration)
    case invalid(message: String)
}

enum DefaultGoogleOAuthConfigurationLoader {
    private static let resourceName = "DefaultGoogleOAuth"

    static func load(bundle: Bundle = .main) throws -> DefaultGoogleOAuthConfiguration {
        guard let url = bundle.url(forResource: resourceName, withExtension: "plist") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        guard let payload = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }

        guard let clientID = payload["CLIENT_ID"] as? String, !clientID.isEmpty else {
            throw CocoaError(.coderInvalidValue)
        }

        guard let reversedClientID = payload["REVERSED_CLIENT_ID"] as? String, !reversedClientID.isEmpty else {
            throw CocoaError(.coderInvalidValue)
        }

        let serverClientID = (payload["SERVER_CLIENT_ID"] as? String)?.nilIfBlank

        return DefaultGoogleOAuthConfiguration(
            clientID: clientID,
            reversedClientID: reversedClientID,
            serverClientID: serverClientID
        )
    }
}

enum GoogleOAuthConfigurationResolver {
    static func resolve(
        defaultConfiguration: DefaultGoogleOAuthConfiguration,
        overrideConfiguration: GoogleOAuthOverrideConfiguration
    ) -> GoogleOAuthConfigurationResolution {
        guard overrideConfiguration.usesCustomApp else {
            return .valid(
                ResolvedGoogleOAuthConfiguration(
                    source: .bundledDefault,
                    clientID: defaultConfiguration.clientID,
                    reversedClientID: defaultConfiguration.reversedClientID,
                    serverClientID: defaultConfiguration.serverClientID
                )
            )
        }

        guard let customClientID = overrideConfiguration.clientID.nilIfBlank else {
            return .invalid(message: "Enter a Google iOS/macOS client ID to use a custom OAuth app.")
        }

        guard let reversedClientID = reversedClientID(for: customClientID) else {
            return .invalid(message: "The custom Google client ID is not in the expected iOS/macOS format.")
        }

        guard reversedClientID == defaultConfiguration.reversedClientID else {
            return .invalid(
                message: "This build is registered for callback scheme \(defaultConfiguration.reversedClientID). A different Google iOS/macOS client ID requires rebuilding the app with its reversed client ID in Info.plist."
            )
        }

        return .valid(
            ResolvedGoogleOAuthConfiguration(
                source: .customOverride,
                clientID: customClientID,
                reversedClientID: reversedClientID,
                serverClientID: overrideConfiguration.serverClientID.nilIfBlank ?? defaultConfiguration.serverClientID
            )
        )
    }

    static func reversedClientID(for clientID: String) -> String? {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let components = trimmed.split(separator: ".").map(String.init)
        guard components.count >= 2 else {
            return nil
        }

        return components.reversed().joined(separator: ".")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

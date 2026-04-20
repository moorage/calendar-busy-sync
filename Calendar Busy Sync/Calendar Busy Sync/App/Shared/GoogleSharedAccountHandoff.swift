import Foundation

struct SharedGoogleAccountDescriptor: Codable, Equatable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let usesCustomOAuthApp: Bool
    let selectedCalendarID: String?
    let selectedCalendarDisplayName: String?
}

enum GoogleSharedAccountHandoff {
    static func reconciledDescriptors(
        currentDescriptors: [SharedGoogleAccountDescriptor],
        localAccounts: [StoredGoogleAccount],
        googleSelectedCalendarIDs: [String: String],
        googleCalendarsByAccountID: [String: [GoogleCalendarSummary]]
    ) -> [SharedGoogleAccountDescriptor] {
        var remainingDescriptors = currentDescriptors
        var reconciled: [SharedGoogleAccountDescriptor] = []

        for account in localAccounts {
            let matchingIndex = remainingDescriptors.firstIndex(where: { descriptor in
                matches(descriptor: descriptor, accountID: account.id, email: account.email)
            })
            let existingDescriptor = matchingIndex.map { remainingDescriptors.remove(at: $0) }
            let selectedCalendarID = selectedCalendarID(
                for: account.id,
                selectedCalendarIDs: googleSelectedCalendarIDs,
                fallback: existingDescriptor?.selectedCalendarID
            )
            let selectedCalendarDisplayName = selectedCalendarName(
                for: account.id,
                selectedCalendarID: selectedCalendarID,
                googleCalendarsByAccountID: googleCalendarsByAccountID,
                fallback: existingDescriptor?.selectedCalendarDisplayName
            )

            reconciled.append(
                SharedGoogleAccountDescriptor(
                    id: account.id,
                    email: account.email,
                    displayName: account.displayName,
                    usesCustomOAuthApp: account.usesCustomOAuthApp,
                    selectedCalendarID: selectedCalendarID,
                    selectedCalendarDisplayName: selectedCalendarDisplayName
                )
            )
        }

        reconciled.append(contentsOf: remainingDescriptors)
        return deduplicated(descriptors: reconciled)
    }

    static func migratedSelectedCalendarIDs(
        currentSelectedCalendarIDs: [String: String],
        connectedAccount: StoredGoogleAccount,
        sharedDescriptors: [SharedGoogleAccountDescriptor]
    ) -> [String: String] {
        guard let matchingDescriptor = matchingDescriptor(
            forAccountID: connectedAccount.id,
            email: connectedAccount.email,
            descriptors: sharedDescriptors
        ) else {
            return currentSelectedCalendarIDs
        }

        var migrated = currentSelectedCalendarIDs
        if matchingDescriptor.id != connectedAccount.id {
            migrated[matchingDescriptor.id] = nil
        }

        if let selectedCalendarID = matchingDescriptor.selectedCalendarID {
            migrated[connectedAccount.id] = selectedCalendarID
        }

        return migrated
    }

    static func matchingDescriptor(
        forAccountID accountID: String,
        email: String,
        descriptors: [SharedGoogleAccountDescriptor]
    ) -> SharedGoogleAccountDescriptor? {
        descriptors.first(where: { descriptor in
            matches(descriptor: descriptor, accountID: accountID, email: email)
        })
    }

    private static func matches(
        descriptor: SharedGoogleAccountDescriptor,
        accountID: String,
        email: String
    ) -> Bool {
        descriptor.id == accountID
            || descriptor.email.compare(email, options: .caseInsensitive) == .orderedSame
    }

    private static func selectedCalendarID(
        for accountID: String,
        selectedCalendarIDs: [String: String],
        fallback: String?
    ) -> String? {
        if let selectedCalendarID = selectedCalendarIDs[accountID] {
            return selectedCalendarID.nilIfEmpty
        }

        return fallback?.nilIfEmpty
    }

    private static func selectedCalendarName(
        for accountID: String,
        selectedCalendarID: String?,
        googleCalendarsByAccountID: [String: [GoogleCalendarSummary]],
        fallback: String?
    ) -> String? {
        guard let selectedCalendarID else {
            return nil
        }

        return googleCalendarsByAccountID[accountID]?
            .first(where: { $0.id == selectedCalendarID })?
            .displayName
            ?? fallback?.nilIfEmpty
    }

    private static func deduplicated(
        descriptors: [SharedGoogleAccountDescriptor]
    ) -> [SharedGoogleAccountDescriptor] {
        var seenKeys = Set<String>()
        var result: [SharedGoogleAccountDescriptor] = []

        for descriptor in descriptors {
            let key = descriptor.id + "|" + descriptor.email.lowercased()
            if seenKeys.insert(key).inserted {
                result.append(descriptor)
            }
        }

        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

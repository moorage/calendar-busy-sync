import Foundation

enum GoogleAccountRosterRowKind: Equatable {
    case connected
    case needsLocalConnection
    case removedFromShared
}

struct GoogleAccountRosterRowModel: Identifiable, Equatable {
    let stableAccountID: String
    let displayName: String
    let email: String
    let usesCustomOAuthApp: Bool
    let kind: GoogleAccountRosterRowKind
    let localCard: GoogleAccountCardModel?
    let sharedDescriptor: SharedGoogleAccountDescriptor?

    var id: String {
        "\(kind.rawValue)-\(stableAccountID)"
    }

    var selectedCalendarDisplayName: String? {
        localCard?.selectedCalendar?.displayName ?? sharedDescriptor?.selectedCalendarDisplayName
    }

    var needsAttention: Bool {
        switch kind {
        case .connected:
            return localCard?.needsAttention ?? true
        case .needsLocalConnection:
            return true
        case .removedFromShared:
            return false
        }
    }

    var countsTowardSetup: Bool {
        kind != .removedFromShared
    }

    var isConnectedLocally: Bool {
        localCard != nil
    }
}

enum GoogleAccountRosterBuilder {
    static func build(
        localCards: [GoogleAccountCardModel],
        sharedDescriptors: [SharedGoogleAccountDescriptor],
        isSharedConfigurationEnabled: Bool
    ) -> [GoogleAccountRosterRowModel] {
        guard isSharedConfigurationEnabled else {
            return localCards.map { card in
                GoogleAccountRosterRowModel(
                    stableAccountID: card.account.id,
                    displayName: card.account.displayName,
                    email: card.account.email,
                    usesCustomOAuthApp: card.account.usesCustomOAuthApp,
                    kind: .connected,
                    localCard: card,
                    sharedDescriptor: nil
                )
            }
        }

        var unmatchedLocalCards = localCards
        var rows: [GoogleAccountRosterRowModel] = []

        for descriptor in sharedDescriptors {
            if let localIndex = unmatchedLocalCards.firstIndex(where: { card in
                card.account.id == descriptor.id
                    || card.account.email.compare(descriptor.email, options: .caseInsensitive) == .orderedSame
            }) {
                let localCard = unmatchedLocalCards.remove(at: localIndex)
                rows.append(
                    GoogleAccountRosterRowModel(
                        stableAccountID: localCard.account.id,
                        displayName: localCard.account.displayName,
                        email: localCard.account.email,
                        usesCustomOAuthApp: localCard.account.usesCustomOAuthApp,
                        kind: .connected,
                        localCard: localCard,
                        sharedDescriptor: descriptor
                    )
                )
            } else {
                rows.append(
                    GoogleAccountRosterRowModel(
                        stableAccountID: descriptor.id,
                        displayName: descriptor.displayName,
                        email: descriptor.email,
                        usesCustomOAuthApp: descriptor.usesCustomOAuthApp,
                        kind: .needsLocalConnection,
                        localCard: nil,
                        sharedDescriptor: descriptor
                    )
                )
            }
        }

        rows.append(
            contentsOf: unmatchedLocalCards.map { card in
                GoogleAccountRosterRowModel(
                    stableAccountID: card.account.id,
                    displayName: card.account.displayName,
                    email: card.account.email,
                    usesCustomOAuthApp: card.account.usesCustomOAuthApp,
                    kind: .removedFromShared,
                    localCard: card,
                    sharedDescriptor: nil
                )
            }
        )

        return rows
    }
}

private extension GoogleAccountRosterRowKind {
    var rawValue: String {
        switch self {
        case .connected:
            return "connected"
        case .needsLocalConnection:
            return "needs-local-connection"
        case .removedFromShared:
            return "removed-from-shared"
        }
    }
}

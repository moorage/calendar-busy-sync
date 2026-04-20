import Foundation

struct ConnectedAccountListEntry: Identifiable, Equatable {
    let id: String
    let providerLabel: String
    let displayName: String
    let detail: String?
    let selectedCalendars: [SelectedCalendar]
}

enum ConnectedAccountListBuilder {
    static func build(
        scenarioAccounts: [ConnectedAccountScenario],
        appleCalendarEnabled: Bool,
        appleCalendarAuthorizationState: AppleCalendarAuthorizationState,
        selectedAppleCalendar: AppleCalendarSummary?,
        googleAccountCards: [GoogleAccountCardModel]
    ) -> [ConnectedAccountListEntry] {
        var accounts = scenarioAccounts.map { scenarioAccount in
            ConnectedAccountListEntry(
                id: scenarioAccount.id,
                providerLabel: scenarioAccount.provider.capitalized,
                displayName: scenarioAccount.displayName,
                detail: nil,
                selectedCalendars: scenarioAccount.selectedCalendars
            )
        }

        if appleCalendarEnabled {
            let selectedCalendars = selectedAppleCalendar.map {
                [SelectedCalendar(id: $0.id, name: $0.displayName, role: .destination)]
            } ?? []
            accounts.append(
                ConnectedAccountListEntry(
                    id: "live-apple-calendar",
                    providerLabel: "Apple / iCloud",
                    displayName: "Apple / iCloud Calendar",
                    detail: appleDetail(
                        authorizationState: appleCalendarAuthorizationState,
                        selectedAppleCalendar: selectedAppleCalendar
                    ),
                    selectedCalendars: selectedCalendars
                )
            )
        }

        for googleAccountCard in googleAccountCards {
            let selectedCalendars = googleAccountCard.selectedCalendar.map {
                [SelectedCalendar(id: $0.id, name: $0.displayName, role: .destination)]
            } ?? []
            accounts.append(
                ConnectedAccountListEntry(
                    id: "live-google-\(googleAccountCard.account.id)",
                    providerLabel: "Google",
                    displayName: googleAccountCard.account.displayName,
                    detail: googleAccountCard.account.email,
                    selectedCalendars: selectedCalendars
                )
            )
        }

        return accounts
    }

    private static func appleDetail(
        authorizationState: AppleCalendarAuthorizationState,
        selectedAppleCalendar: AppleCalendarSummary?
    ) -> String {
        switch authorizationState {
        case .granted:
            return selectedAppleCalendar?.sourceDisplayName ?? "Connected on this device"
        case .denied:
            return "Calendar permission denied"
        case .restricted:
            return "Calendar permission restricted"
        case .notDetermined:
            return "Waiting for calendar permission"
        }
    }
}

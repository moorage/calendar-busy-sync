import Foundation

struct GoogleAccountCardModel: Identifiable, Equatable {
    let account: GoogleConnectedAccount
    let calendars: [GoogleCalendarSummary]
    let selectedCalendarID: String
    let message: String?
    let lastManagedEvent: GoogleManagedEventRecord?
    let isOperationInFlight: Bool
    let isActive: Bool

    var id: String {
        account.id
    }

    var selectedCalendar: GoogleCalendarSummary? {
        calendars.first(where: { $0.id == selectedCalendarID })
    }

    var statusLabel: String {
        if isOperationInFlight {
            return "Working…"
        }

        if calendars.isEmpty {
            return "No calendars loaded"
        }

        if selectedCalendar == nil {
            return "Select a calendar"
        }

        return "Ready"
    }

    var needsAttention: Bool {
        calendars.isEmpty || selectedCalendar == nil
    }

    var detail: String {
        if let selectedCalendar {
            return "Destination calendar: \(selectedCalendar.displayName)"
        }

        if calendars.isEmpty {
            return "Load writable calendars for this account, then choose where mirrored busy slots should be written."
        }

        return "Choose which calendar in this Google account should receive mirrored busy slots."
    }

    var metadataLine: String {
        let scopeCount = account.grantedScopes.count
        let scopeSummary = scopeCount == 1 ? "1 scope granted" : "\(scopeCount) scopes granted"

        if account.usesCustomOAuthApp {
            return "\(account.email) • \(scopeSummary) • Custom OAuth"
        }

        return "\(account.email) • \(scopeSummary)"
    }

    var canRefreshCalendars: Bool {
        !isOperationInFlight
    }

    var canCreateManagedBusyEvent: Bool {
        selectedCalendar != nil && !isOperationInFlight
    }

    var canDeleteManagedBusyEvent: Bool {
        lastManagedEvent != nil && !isOperationInFlight
    }
}

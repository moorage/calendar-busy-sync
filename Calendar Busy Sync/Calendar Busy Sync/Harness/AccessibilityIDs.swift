import Foundation

enum AccessibilityIDs {
    static let accountsList = "accounts.list"
    static let syncStatusLastRun = "sync-status.last-run"
    static let syncStatusPendingCount = "sync-status.pending-count"
    static let syncStatusFailedCount = "sync-status.failed-count"
    static let mirrorPreviewList = "mirror-preview.list"
    static let mirrorPreviewBusyLabel = "mirror-preview.busy-label"

    static func accountRow(_ id: String) -> String {
        "calendar-picker.account.\(sanitized(id))"
    }

    static func calendarRow(_ id: String) -> String {
        "calendar-picker.calendar.\(sanitized(id))"
    }

    static func mirrorPreviewRow(_ id: String) -> String {
        "mirror-preview.row.\(sanitized(id))"
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

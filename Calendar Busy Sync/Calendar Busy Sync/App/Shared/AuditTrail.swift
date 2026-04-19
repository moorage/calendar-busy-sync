import Foundation

struct AuditTrailEntry: Identifiable, Equatable {
    let timestampLabel: String
    let title: String
    let detail: String
    let status: String

    var id: String {
        "\(timestampLabel)|\(title)|\(status)"
    }
}

enum AuditTrailBuilder {
    static func entries(
        for state: ScenarioState?,
        platform: HarnessPlatformTarget,
        pollIntervalMinutes: Int,
        auditTrailLogLength: AuditTrailLogLength,
        googleOAuth: GoogleOAuthOverrideConfiguration
    ) -> [AuditTrailEntry] {
        var entries: [AuditTrailEntry] = []

        switch platform {
        case .macos:
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Settings",
                    title: "Polling interval configured",
                    detail: "Automatic sync checks run every \(pollIntervalMinutes) minutes on macOS.",
                    status: "configured"
                )
            )
        case .ios:
            break
        }

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Advanced",
                title: "Google OAuth provider mode",
                detail: googleOAuth.modeSummary,
                status: googleOAuth.usesCustomApp ? "custom" : "default"
            )
        )

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Advanced",
                title: "Audit trail retention",
                detail: auditTrailLogLength.displayLabel,
                status: "configured"
            )
        )

        guard let state else {
            return entries
        }

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Ready",
                title: "Scenario loaded",
                detail: "\(state.connectedAccountCount) accounts, \(state.selectedCalendarCount) selected calendars.",
                status: state.lastSyncStatus
            )
        )

        let previewEntries = state.mirrorPreview.enumerated().map { index, preview in
            AuditTrailEntry(
                timestampLabel: state.auditTimestampLabel(forPreviewAt: index),
                title: "Busy hold planned",
                detail: "\(preview.sourceCalendar) -> \(preview.targetCalendar)",
                status: preview.availability
            )
        }

        entries.append(contentsOf: previewEntries)

        if let limit = auditTrailLogLength.limit, entries.count > limit {
            return Array(entries.suffix(limit))
        }

        return entries
    }
}

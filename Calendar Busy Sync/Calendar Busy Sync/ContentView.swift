import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let state = model.state {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            accountsSection(state: state)
                            previewSection(state: state)
                            statusSection(state: state)
                        }
                        .padding(24)
                    }
                } else if let errorMessage = model.lastErrorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Unable to load scenario")
                            .font(.title2.weight(.semibold))
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                } else {
                    ProgressView("Loading sync scenario…")
                        .padding(24)
                }
            }
            .navigationTitle("Calendar Busy Sync")
        }
    }

    private func accountsSection(state: ScenarioState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Accounts")
                .font(.headline)

            ForEach(state.scenario.accounts) { account in
                VStack(alignment: .leading, spacing: 8) {
                    Text(account.displayName)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier(AccessibilityIDs.accountRow(account.id))

                    ForEach(account.selectedCalendars) { calendar in
                        HStack {
                            Text(calendar.name)
                            Spacer()
                            Text(calendar.role.badgeLabel)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .accessibilityIdentifier(AccessibilityIDs.calendarRow(calendar.id))
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIDs.accountsList)
    }

    private func previewSection(state: ScenarioState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mirror Preview")
                .font(.headline)

            ForEach(state.mirrorPreview) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.sourceCalendar) -> \(entry.targetCalendar)")
                        .font(.subheadline.weight(.medium))
                    Text(entry.availability.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.mirrorPreviewBusyLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityIDs.mirrorPreviewRow(entry.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIDs.mirrorPreviewList)
    }

    private func statusSection(state: ScenarioState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync Status")
                .font(.headline)
            Text("Ready")
                .accessibilityIdentifier(AccessibilityIDs.syncStatusLastRun)
            Text("Pending writes: \(state.pendingWriteCount)")
                .accessibilityIdentifier(AccessibilityIDs.syncStatusPendingCount)
            Text("Failed writes: \(state.failedWriteCount)")
                .accessibilityIdentifier(AccessibilityIDs.syncStatusFailedCount)
        }
    }
}

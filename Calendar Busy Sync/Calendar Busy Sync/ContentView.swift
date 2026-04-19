import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let state = model.state {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            syncSettingsSection
                            appleConnectionSection
                            appleCalendarsSection
                            googleConnectionSection
                            googleCalendarsSection
                            advancedSection
                            auditTrailSection
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

    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            #if os(macOS)
            VStack(alignment: .leading, spacing: 8) {
                Text("Poll Google Calendar for new busy events")
                    .font(.subheadline.weight(.semibold))
                Stepper(value: $model.pollIntervalMinutes, in: 1...60) {
                    Text("Every \(model.pollIntervalMinutes) minutes")
                }
                .accessibilityIdentifier(AccessibilityIDs.syncPollIntervalStepper)

                Text("Polling cadence is configurable on macOS only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #else
            Text("Polling cadence is not user-configurable on iPhone or iPad. Background sync follows iOS scheduling constraints.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var appleConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple / iCloud Calendar")
                .font(.headline)

            Text(model.appleConnectionStatusLabel)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier(AccessibilityIDs.appleCalendarConnectionStatusLabel)

            Text(model.appleConnectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = model.appleCalendarMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarMessageLabel)
            }

            HStack(spacing: 12) {
                Button(model.appleConnectButtonTitle) {
                    Task {
                        await model.connectAppleCalendar()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isAppleCalendarOperationInFlight)
                .accessibilityIdentifier(AccessibilityIDs.appleCalendarConnectButton)

                if model.isAppleCalendarEnabled {
                    Button("Disconnect Apple Calendar") {
                        model.disconnectAppleCalendar()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isAppleCalendarOperationInFlight)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarDisconnectButton)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var googleConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Google Account")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text(model.googleConnectionStatusLabel)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier(AccessibilityIDs.googleAuthStatusLabel)

                Spacer()

                Text(model.googleOAuthConfiguration.modeSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let account = model.googleConnectedAccount {
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(model.googleConnectionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.googleAuthConnectedAccountLabel)
                }
            } else {
                Text(model.googleConnectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let resolutionMessage = model.googleOAuthResolutionMessage {
                Text(resolutionMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(AccessibilityIDs.googleAuthResolutionWarning)
            }

            if let authMessage = model.googleAuthMessage {
                Text(authMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityIDs.googleAuthMessageLabel)
            }

            HStack(spacing: 12) {
                Button(model.googleConnectButtonTitle) {
                    Task {
                        await model.connectGoogleAccount()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartGoogleSignIn)
                .accessibilityIdentifier(AccessibilityIDs.googleAuthConnectButton)

                if model.googleConnectedAccount != nil {
                    Button("Disconnect Google") {
                        Task {
                            await model.disconnectGoogleAccount()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isGoogleAuthInFlight)
                    .accessibilityIdentifier(AccessibilityIDs.googleAuthDisconnectButton)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.headline)

            Toggle("Use your own Google OAuth app", isOn: $model.usesCustomGoogleOAuthApp)
                .accessibilityIdentifier(AccessibilityIDs.googleOAuthUseCustomToggle)

            Text("The app uses shared Google OAuth credentials by default. Advanced users can override them with their own client IDs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.usesCustomGoogleOAuthApp {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Google iOS/macOS client ID", text: $model.customGoogleOAuthClientID)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(AccessibilityIDs.googleOAuthClientIDField)

                    TextField("Google server client ID (optional)", text: $model.customGoogleOAuthServerClientID)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(AccessibilityIDs.googleOAuthServerClientIDField)

                    Text("Custom native client IDs must reuse the callback scheme baked into this app build. A different reversed client ID requires a rebuild.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Audit trail event log length", selection: $model.auditTrailLogLength) {
                ForEach(AuditTrailLogLength.allCases) { option in
                    Text(option.displayLabel).tag(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var appleCalendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple / iCloud Calendars")
                .font(.headline)

            Text(model.appleCalendarStatusLabel)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier(AccessibilityIDs.appleCalendarStatusLabel)

            Text(model.appleCalendarDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.isAppleCalendarEnabled {
                HStack(spacing: 12) {
                    Button("Refresh Calendars") {
                        Task {
                            await model.refreshAppleCalendars()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canRefreshAppleCalendars)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarRefreshButton)

                    Button("Create Test Busy Slot") {
                        Task {
                            await model.createManagedAppleEvent()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canCreateManagedAppleEvent)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarCreateButton)

                    Button("Delete Test Busy Slot") {
                        Task {
                            await model.deleteManagedAppleEvent()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canDeleteManagedAppleEvent)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarDeleteButton)
                }

                if model.appleCalendars.isEmpty {
                    Text("No writable Apple calendars are loaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Write busy slots to",
                        selection: Binding(
                            get: { model.selectedAppleCalendarID },
                            set: { model.selectedAppleCalendarID = $0 }
                        )
                    ) {
                        ForEach(model.appleCalendars) { calendar in
                            Text(calendar.displayName).tag(calendar.id)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarPicker)
                }

                if let lastManagedEvent = model.lastManagedAppleEvent {
                    Text("\(lastManagedEvent.summary) • \(lastManagedEvent.windowDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.appleCalendarLastEventLabel)
                }
            } else {
                Text("Connect Apple Calendar to choose a writable Apple or iCloud calendar and verify event writes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var googleCalendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Google Calendars")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text(model.googleCalendarStatusLabel)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarStatusLabel)

                Spacer()

                if let status = model.liveGoogleSmokeStatusLabel {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.googleCalendarLiveSmokeStatusLabel)
                }
            }

            Text(model.googleCalendarDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let smokeSummary = model.liveGoogleSmokeSummary {
                Text(smokeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let googleCalendarMessage = model.googleCalendarMessage {
                Text(googleCalendarMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarMessageLabel)
            }

            if model.googleConnectedAccount != nil {
                HStack(spacing: 12) {
                    Button("Refresh Calendars") {
                        Task {
                            await model.refreshGoogleCalendars()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canRefreshGoogleCalendars)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarRefreshButton)

                    Button("Create Test Busy Slot") {
                        Task {
                            await model.createManagedBusyEvent()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canCreateManagedBusyEvent)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarCreateButton)

                    Button("Delete Test Busy Slot") {
                        Task {
                            await model.deleteManagedBusyEvent()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canDeleteManagedBusyEvent)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarDeleteButton)
                }

                if model.googleCalendars.isEmpty {
                    Text("No writable Google calendars are loaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Write busy slots to",
                        selection: Binding(
                            get: { model.selectedGoogleCalendarID },
                            set: { model.selectedGoogleCalendarID = $0 }
                        )
                    ) {
                        ForEach(model.googleCalendars) { calendar in
                            Text(calendar.displayName).tag(calendar.id)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarPicker)
                }

                if let lastManagedEvent = model.lastManagedGoogleEvent {
                    Text("\(lastManagedEvent.summary) • \(lastManagedEvent.windowDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.googleCalendarLastEventLabel)
                }
            } else {
                Text("Connect Google to choose a writable calendar and verify event writes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var auditTrailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audit Trail")
                .font(.headline)

            ForEach(model.auditTrailEntries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.timestampLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(entry.status.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIDs.auditTrailList)
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

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
                            googleAccountsSection
                            advancedSection
                            auditTrailSection
                            accountsSection
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

                if model.canOpenAppleCalendarSettings {
                    Button("Open Calendar Settings") {
                        model.openAppleCalendarSettings()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarOpenSettingsButton)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var googleAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Google Accounts")
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

            Text(model.googleConnectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

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
                if let status = model.liveGoogleSmokeStatusLabel {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.googleCalendarLiveSmokeStatusLabel)
                }
            }

            if !model.googleAccountCards.isEmpty {
                HStack(spacing: 10) {
                    googleOverviewChip(title: "Connected", value: "\(model.googleAccountCards.count)")
                    googleOverviewChip(title: "Ready", value: "\(model.googleReadyAccountCount)")
                    googleOverviewChip(title: "Needs setup", value: "\(model.googleNeedsAttentionCount)")
                }
            }

            Text(model.googleCalendarStatusLabel)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier(AccessibilityIDs.googleCalendarStatusLabel)

            Text(model.googleCalendarDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let smokeSummary = model.liveGoogleSmokeSummary {
                Text(smokeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.googleAccountCards.isEmpty {
                Text("Add a Google account to choose a writable destination calendar and verify event writes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.googleAccountCards) { card in
                    googleAccountCard(card)
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

    private func googleAccountCard(_ card: GoogleAccountCardModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(card.account.displayName)
                            .font(.subheadline.weight(.semibold))

                        if card.isActive {
                            googleBadge("Primary")
                        }

                        if card.account.usesCustomOAuthApp {
                            googleBadge("Custom OAuth")
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIDs.googleAccountCard(card.id))

                    Text(card.metadataLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(card.statusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !card.isActive {
                        Button("Make Primary") {
                            model.setActiveGoogleAccount(card.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.medium))
                        .accessibilityIdentifier(AccessibilityIDs.googleAccountPrimaryButton(card.id))
                    }
                }
            }

            Text(card.detail)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Destination calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if card.calendars.isEmpty {
                    Text("No writable Google calendars are loaded yet for this account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Write busy slots to",
                        selection: Binding(
                            get: { model.selectedGoogleCalendarID(for: card.id) },
                            set: { model.setSelectedGoogleCalendarID($0, for: card.id) }
                        )
                    ) {
                        ForEach(card.calendars) { calendar in
                            Text(calendar.displayName).tag(calendar.id)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarPicker(card.id))
                }
            }

            if let message = card.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarMessageLabel(card.id))
            }

            if let lastManagedEvent = card.lastManagedEvent {
                Text("\(lastManagedEvent.summary) • \(lastManagedEvent.windowDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarLastEventLabel(card.id))
            }

            HStack(spacing: 12) {
                Button("Refresh Calendars") {
                    Task {
                        await model.refreshGoogleCalendars(for: card.id)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!card.canRefreshCalendars)
                .accessibilityIdentifier(AccessibilityIDs.googleCalendarRefreshButton(card.id))

                Button("Create Test Busy Slot") {
                    Task {
                        await model.createManagedBusyEvent(for: card.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!card.canCreateManagedBusyEvent)
                .accessibilityIdentifier(AccessibilityIDs.googleCalendarCreateButton(card.id))

                Button("Delete Test Busy Slot") {
                    Task {
                        await model.deleteManagedBusyEvent(for: card.id)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!card.canDeleteManagedBusyEvent)
                .accessibilityIdentifier(AccessibilityIDs.googleCalendarDeleteButton(card.id))

                Spacer()

                Button("Remove Account") {
                    model.removeGoogleAccount(card.id)
                }
                .buttonStyle(.bordered)
                .disabled(model.isGoogleAuthInFlight)
                .accessibilityIdentifier(AccessibilityIDs.googleAuthDisconnectButton(card.id))
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func googleOverviewChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func googleBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
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

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Accounts")
                .font(.headline)

            if model.connectedAccountsForDisplay.isEmpty {
                Text("No connected accounts are listed yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.connectedAccountsForDisplay) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier(AccessibilityIDs.accountRow(account.id))

                            Spacer()

                            Text(account.providerLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if let detail = account.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if account.selectedCalendars.isEmpty {
                            Text("No calendar selected yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
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
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
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

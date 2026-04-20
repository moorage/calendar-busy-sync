import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            Group {
                if let state = model.state {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            googleAccountsSection
                            appleCalendarSection
                            advancedSection

                            if !state.mirrorPreview.isEmpty {
                                previewSection(state: state)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 28)
                    }
                } else if let errorMessage = model.lastErrorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Unable to Load Scenario", systemImage: "exclamationmark.triangle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                } else {
                    ProgressView("Loading Calendar Busy Sync…")
                        .padding(24)
                }
            }
            .navigationTitle("Calendar Busy Sync")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.state != nil {
                statusLine
            }
        }
    }

    private var googleAccountsSection: some View {
        settingsSection {
            sectionHeader(
                title: "Google Accounts",
                icon: { providerBadge(assetName: "GoogleBadge") }
            ) {
                Button {
                    Task {
                        await model.connectGoogleAccount()
                    }
                } label: {
                    Label("Add Google Account", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canStartGoogleSignIn)
                .accessibilityIdentifier(AccessibilityIDs.googleAuthConnectButton)
            }

            if let resolutionMessage = model.googleOAuthResolutionMessage {
                sectionDivider
                infoMessageRow(
                    resolutionMessage,
                    timestamp: nil,
                    tint: .orange,
                    accessibilityID: AccessibilityIDs.googleAuthResolutionWarning
                )
            }

            if let authMessage = model.googleAuthMessage {
                sectionDivider
                infoMessageRow(
                    authMessage,
                    timestamp: model.googleAuthMessageTimestampLabel,
                    accessibilityID: AccessibilityIDs.googleAuthMessageLabel
                )
            }

            if let status = model.liveGoogleSmokeStatusLabel, let summary = model.liveGoogleSmokeSummary {
                sectionDivider
                sectionRow {
                    HStack(spacing: 10) {
                        Image(systemName: model.currentActivityIconName)
                            .foregroundStyle(.secondary)
                        Text(status)
                            .fontWeight(.medium)
                            .accessibilityIdentifier(AccessibilityIDs.googleCalendarLiveSmokeStatusLabel)
                        Text(summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.caption)
                }
            }

            if model.googleAccountCards.isEmpty {
                sectionDivider
                sectionRow {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(.secondary)
                        Text("Add an account, then choose a calendar.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .font(.caption)
                }
            } else {
                ForEach(model.googleAccountCards) { card in
                    sectionDivider
                    googleAccountRow(card)
                }
            }
        }
    }

    private var appleCalendarSection: some View {
        settingsSection {
            sectionHeader(
                title: "Apple / iCloud Calendar",
                icon: { providerBadge(assetName: "ICloudBadge") }
            )

            if model.isAppleCalendarEnabled {
                sectionRow {
                    appleCalendarSelectionRow
                }

                sectionDivider
                sectionRow {
                    HStack(spacing: 10) {
                        if model.canOpenAppleCalendarSettings {
                            Button {
                                Task {
                                    await model.openAppleCalendarSettings()
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(AccessibilityIDs.appleCalendarOpenSettingsButton)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            model.disconnectAppleCalendar()
                        } label: {
                            Label("Disconnect", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isAppleCalendarOperationInFlight)
                        .accessibilityIdentifier(AccessibilityIDs.appleCalendarDisconnectButton)
                    }
                    .font(.caption)
                }
            } else {
                sectionRow {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await model.connectAppleCalendar()
                            }
                        } label: {
                            Label("Connect Apple Calendar", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isAppleCalendarOperationInFlight)
                        .accessibilityIdentifier(AccessibilityIDs.appleCalendarConnectButton)

                        if model.canOpenAppleCalendarSettings {
                            Button {
                                Task {
                                    await model.openAppleCalendarSettings()
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(AccessibilityIDs.appleCalendarOpenSettingsButton)
                        }

                        Spacer()
                    }
                    .font(.caption)
                }
            }

            if let message = model.appleCalendarMessage {
                sectionDivider
                infoMessageRow(
                    message,
                    timestamp: model.appleCalendarMessageTimestampLabel,
                    accessibilityID: AccessibilityIDs.appleCalendarMessageLabel
                )
            }
        }
    }

    private var advancedSection: some View {
        settingsSection {
            sectionHeader(
                title: "Advanced",
                icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            )

            sectionRow {
                HStack(spacing: 12) {
                    Label("Use your own Google OAuth app", systemImage: "lock.open.display")
                    Spacer()
                    Toggle("", isOn: $model.usesCustomGoogleOAuthApp)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier(AccessibilityIDs.googleOAuthUseCustomToggle)
                }
                .font(.caption)
            }

            if model.usesCustomGoogleOAuthApp {
                sectionDivider
                sectionRow {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Google iOS/macOS client ID", text: $model.customGoogleOAuthClientID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AccessibilityIDs.googleOAuthClientIDField)

                        TextField("Google server client ID (optional)", text: $model.customGoogleOAuthServerClientID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AccessibilityIDs.googleOAuthServerClientIDField)
                    }
                }
            }

            #if os(macOS)
            sectionDivider
            sectionRow {
                adaptiveTrailingRow(label: {
                    Label("Polling", systemImage: "timer")
                        .foregroundStyle(.secondary)
                }, trailing: {
                    Stepper(value: $model.pollIntervalMinutes, in: 1...60) {
                        Text("Every \(model.pollIntervalMinutes) minutes")
                    }
                    .accessibilityIdentifier(AccessibilityIDs.syncPollIntervalStepper)
                })
                .font(.caption)
            }
            #endif

            sectionDivider
            sectionRow {
                adaptiveTrailingRow(label: {
                    Label("Log Retention", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }, trailing: {
                    Picker("Audit trail event log length", selection: $model.auditTrailLogLength) {
                        ForEach(AuditTrailLogLength.allCases) { option in
                            Text(option.displayLabel).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                })
                .font(.caption)
            }
        }
    }

    private func googleAccountRow(_ card: GoogleAccountCardModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                adaptiveTrailingRow(label: {
                    accountIdentityRow(
                        title: card.account.displayName,
                        subtitle: card.account.email
                    )
                    .accessibilityIdentifier(AccessibilityIDs.googleAccountCard(card.id))
                }, trailing: {
                    HStack(spacing: 8) {
                        Button(role: .destructive) {
                            model.removeGoogleAccount(card.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isGoogleAuthInFlight)
                        .accessibilityIdentifier(AccessibilityIDs.googleAuthDisconnectButton(card.id))
                    }
                })
                .font(.caption)

            if card.calendars.isEmpty {
                adaptiveTrailingRow(label: {
                    HStack(spacing: 8) {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                        Text("No calendars loaded")
                            .accessibilityIdentifier(AccessibilityIDs.googleCalendarStatusLabel)
                    }
                }, trailing: {
                    Button {
                        Task {
                            await model.refreshGoogleCalendars(for: card.id)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!card.canRefreshCalendars)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarRefreshButton(card.id))
                })
                .font(.caption)
            } else {
                adaptiveTrailingRow(label: {
                    HStack(spacing: 8) {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.selectedGoogleCalendarID(for: card.id) },
                                set: { model.setSelectedGoogleCalendarID($0, for: card.id) }
                            )
                        ) {
                            ForEach(card.calendars) { calendar in
                                Text(calendar.displayName).tag(calendar.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityIdentifier(AccessibilityIDs.googleCalendarPicker(card.id))
                    }
                }, trailing: {
                    Button {
                        Task {
                            await model.refreshGoogleCalendars(for: card.id)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!card.canRefreshCalendars)
                    .accessibilityIdentifier(AccessibilityIDs.googleCalendarRefreshButton(card.id))
                })
                .font(.caption)
            }

            if let message = card.message {
                infoMessageRow(
                    message,
                    timestamp: card.messageTimestampLabel,
                    accessibilityID: AccessibilityIDs.googleCalendarMessageLabel(card.id)
                )
            }
        }
    }

    private var appleCalendarSelectionRow: some View {
        Group {
            if model.appleCalendars.isEmpty {
                adaptiveTrailingRow(label: {
                    HStack(spacing: 8) {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                        Text("No calendars loaded")
                            .accessibilityIdentifier(AccessibilityIDs.appleCalendarStatusLabel)
                    }
                }, trailing: {
                    Button {
                        Task {
                            await model.refreshAppleCalendars()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canRefreshAppleCalendars)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarRefreshButton)
                })
                .font(.caption)
            } else {
                adaptiveTrailingRow(label: {
                    HStack(spacing: 8) {
                        Label("Calendar", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.selectedAppleCalendarID },
                                set: { model.selectedAppleCalendarID = $0 }
                            )
                        ) {
                            ForEach(model.appleCalendars) { calendar in
                                Text(calendar.displayName).tag(calendar.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityIdentifier(AccessibilityIDs.appleCalendarPicker)
                    }
                }, trailing: {
                    Button {
                        Task {
                            await model.refreshAppleCalendars()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canRefreshAppleCalendars)
                    .accessibilityIdentifier(AccessibilityIDs.appleCalendarRefreshButton)
                })
                .font(.caption)
            }
        }
    }

    private func previewSection(state: ScenarioState) -> some View {
        settingsSection {
            sectionHeader(
                title: "Mirror Preview",
                icon: {
                    Image(systemName: "rectangle.3.group.bubble.left")
                        .foregroundStyle(.secondary)
                }
            )

            ForEach(Array(state.mirrorPreview.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    sectionDivider
                }

                sectionRow {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.secondary)
                        Text("\(entry.sourceCalendar) -> \(entry.targetCalendar)")
                        Spacer()
                        Text(entry.availability.capitalized)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(AccessibilityIDs.mirrorPreviewBusyLabel)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityIDs.mirrorPreviewRow(entry.id))
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIDs.mirrorPreviewList)
    }

    private var statusLine: some View {
        HStack(spacing: 14) {
            Label(model.currentActivitySummary, systemImage: model.currentActivityIconName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .accessibilityIdentifier(AccessibilityIDs.syncStatusDetail)

            Spacer(minLength: 8)

            Label(model.pendingActivityLabel, systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .accessibilityIdentifier(AccessibilityIDs.syncStatusPendingCount)

            Label(
                model.failureCountLabel,
                systemImage: model.failureCount == 0 ? "checkmark.circle" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundColor(model.failureCount == 0 ? .secondary : .red)
            .accessibilityIdentifier(AccessibilityIDs.syncStatusFailedCount)

            Button {
                openWindow(id: AppSceneIDs.auditTrail)
            } label: {
                Label("Logs", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityIDs.auditTrailOpenButton)

            Button {
                Task {
                    await model.syncNow()
                }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!model.canSyncNow)
            .accessibilityIdentifier(AccessibilityIDs.syncNowButton)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func settingsSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background(sectionBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(sectionStrokeColor, lineWidth: 1)
        }
    }

    private func sectionHeader<Icon: View, Actions: View>(
        title: String,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            icon()
            Text(title)
                .font(.headline)
            Spacer()
            actions()
        }
        .padding(.bottom, 8)
    }

    private var sectionDivider: some View {
        Divider()
    }

    private func sectionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private func adaptiveTrailingRow<LabelContent: View, TrailingContent: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder trailing: () -> TrailingContent
    ) -> some View {
        ViewThatFits {
            HStack(spacing: 12) {
                label()
                Spacer(minLength: 10)
                trailing()
            }

            VStack(alignment: .leading, spacing: 10) {
                label()
                trailing()
            }
        }
    }

    private func accountIdentityRow(
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fontWeight(.medium)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func infoMessageRow(
        _ message: String,
        timestamp: String?,
        tint: Color = .secondary,
        accessibilityID: String
    ) -> some View {
        sectionRow {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(tint)
                Text(message)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let timestamp {
                    Text(timestamp)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .padding(.leading, 22)
            .accessibilityIdentifier(accessibilityID)
        }
    }

    private func providerBadge(assetName: String, size: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: size * 0.38, style: .continuous)
            .fill(Color.white)
            .frame(width: size + 14, height: size + 14)
            .overlay {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.38, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
    }

    private var sectionBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    private var sectionStrokeColor: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.35)
        #else
        Color(uiColor: .separator).opacity(0.35)
        #endif
    }
}

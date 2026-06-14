import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @State private var isMobileStatusSheetPresented = false
    @State private var isBookingSettingsPresented = false
    @State private var isBookingHistoryPresented = false
    @State private var bookingWorkspaceSection: BookingWorkspaceSection = .overview
    @State private var bookingInboxSetupMode: BookingInboxSetupMode = .existing
    @State private var isBookingAppointmentTypeDetailVisible = false
    @State private var isBookingDurationSectionExpanded = false
    @State private var isBookingLocationSectionExpanded = false
    @State private var isBookingAvailabilitySectionExpanded = false
    @State private var isBookingCustomizationBoundariesExpanded = false
    @State private var isBookingPublishConfirmationPresented = false

    private enum BookingWorkspaceSection: String, CaseIterable, Identifiable {
        case overview
        case appointmentTypes
        case pageFiles
        case publish
        case requestInbox
        case history

        var id: String { rawValue }

        var label: String {
            switch self {
            case .overview: return "Overview"
            case .appointmentTypes: return BookingCopy.Field.appointmentType
            case .pageFiles: return "Public Page"
            case .publish: return "Publish"
            case .requestInbox: return BookingCopy.StatusCard.inboxTitle
            case .history: return "History"
            }
        }
    }

    private enum BookingInboxSetupMode: String, CaseIterable, Identifiable {
        case existing
        case vercel

        var id: String { rawValue }

        var label: String {
            switch self {
            case .existing:
                return "Use existing inbox"
            case .vercel:
                return "Guided Vercel deploy"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let state = model.state {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            googleAccountsSection
                            appleCalendarSection
                            bookingSection
                            advancedSection

                            if !state.mirrorPreview.isEmpty {
                                previewSection(state: state)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, scrollContentBottomPadding)
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
        .sheet(isPresented: $isBookingSettingsPresented) {
            bookingSettingsSheet
        }
        .sheet(isPresented: $isBookingHistoryPresented) {
            bookingHistorySheet
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
                    Label(addGoogleAccountButtonTitle, systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(usesCompactMobileLayout ? .small : .regular)
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

            if model.googleAccountRosterRows.isEmpty {
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
                ForEach(model.googleAccountRosterRows) { row in
                    sectionDivider
                    googleAccountRow(row)
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

    private var bookingSection: some View {
        settingsSection {
            sectionHeader(
                title: BookingCopy.Settings.title,
                icon: {
                    Image(systemName: BookingIconography.settings.primarySystemName)
                        .foregroundStyle(.secondary)
                },
                actions: {
                    Button {
                        bookingWorkspaceSection = .overview
                        isBookingSettingsPresented = true
                    } label: {
                        Label("Open booking", systemImage: BookingIconography.advanced.primarySystemName)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityIDs.bookingSettingsButton)
                }
            )

            sectionRow {
                Text(BookingCopy.Settings.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityIDs.bookingSubtitleLabel)
            }

            sectionDivider
            sectionRow {
                adaptiveTrailingRow(label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.bookingSetupSnapshot.isReady ? BookingIconography.ready.primarySystemName : BookingIconography.settings.primarySystemName)
                            .foregroundStyle(model.bookingSetupSnapshot.isReady ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.bookingSetupSnapshot.headline)
                                .fontWeight(.medium)
                            Text(model.bookingSetupSnapshot.detail)
                                .foregroundStyle(.secondary)
                        }
                    }
                }, trailing: {
                    Button {
                        bookingWorkspaceSection = .overview
                        isBookingSettingsPresented = true
                    } label: {
                        Label("Open checklist", systemImage: BookingIconography.settings.primarySystemName)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityIDs.bookingSetupButton)
                })
                .font(.caption)
            }

            sectionDivider
            bookingPageStatusRow

            sectionDivider
            bookingStatusRow(
                title: BookingCopy.StatusCard.inboxTitle,
                status: model.bookingInboxStatusLabel,
                icon: BookingIconography.inbox.primarySystemName,
                accessibilityID: AccessibilityIDs.bookingInboxStatusLabel
            )

            sectionDivider
            bookingStatusRow(
                title: BookingCopy.StatusCard.requestsTitle,
                status: model.bookingRequestsStatusLabel,
                icon: BookingIconography.requests.primarySystemName,
                accessibilityID: AccessibilityIDs.bookingRequestsStatusLabel
            )

            if let message = model.bookingSetupSnapshot.lastMessage {
                sectionDivider
                infoMessageRow(
                    message,
                    timestamp: nil,
                    accessibilityID: AccessibilityIDs.bookingMessageLabel
                )
            }

            if model.hasBookingRequestHistory {
                sectionDivider
                sectionRow {
                    adaptiveTrailingRow(label: {
                        Label("Request history", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    }, trailing: {
                        Button {
                            bookingWorkspaceSection = .history
                            isBookingSettingsPresented = true
                        } label: {
                            Label(BookingCopy.Action.viewRequestHistory, systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(AccessibilityIDs.bookingRequestHistoryButton)
                    })
                    .font(.caption)
                }
            }

            if model.hasActiveBookingRequests {
                sectionDivider
                sectionRow {
                    bookingRequestList(model.activeBookingRequests, allowsActions: true)
                }
            }

            sectionDivider
            sectionRow {
                ViewThatFits {
                    HStack(spacing: 10) {
                        bookingActionButtons
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        bookingActionButtons
                    }
                }
                .font(.caption)
            }
        }
        .accessibilityIdentifier(AccessibilityIDs.bookingSection)
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

            sectionDivider
            sectionRow {
                HStack(spacing: 12) {
                    Label("Share settings through iCloud", systemImage: "icloud")
                    Spacer()
                    Toggle("", isOn: $model.isSharedConfigurationEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier(AccessibilityIDs.sharedConfigurationToggle)
                }
                .font(.caption)
            }

            sectionDivider
            sectionRow {
                adaptiveTrailingRow(label: {
                    Label("iCloud Settings Sync", systemImage: "arrow.clockwise.icloud")
                        .foregroundStyle(.secondary)
                }, trailing: {
                    Text(model.sharedConfigurationStatusLabel)
                        .foregroundStyle(model.sharedConfigurationHasFailureStatus ? .red : .secondary)
                        .accessibilityIdentifier(AccessibilityIDs.sharedConfigurationStatusLabel)
                })
                .font(.caption)
            }

            sectionDivider
            infoMessageRow(
                model.sharedConfigurationStatusMessage,
                timestamp: model.sharedConfigurationStatusTimestampLabel,
                tint: model.sharedConfigurationHasFailureStatus ? .red : .secondary,
                accessibilityID: AccessibilityIDs.sharedConfigurationDetailLabel
            )

            if model.isSharedConfigurationEnabled {
                sectionDivider
                sectionRow {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await model.syncSharedConfigurationNow()
                            }
                        } label: {
                            Label("Sync iCloud Settings Now", systemImage: "arrow.clockwise.icloud")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canManuallySyncSharedConfiguration)
                        .accessibilityIdentifier(AccessibilityIDs.sharedConfigurationSyncNowButton)

                        Spacer()
                    }
                    .font(.caption)
                }

                sectionDivider
                infoMessageRow(
                    model.sharedConfigurationScopeMessage,
                    timestamp: nil,
                    accessibilityID: "settings.advanced.shared-configuration-scope"
                )
            }

            #if os(iOS)
            sectionDivider
            sectionRow {
                adaptiveTrailingRow(label: {
                    Label("Background Refresh", systemImage: "arrow.triangle.2.circlepath.circle")
                        .foregroundStyle(.secondary)
                }, trailing: {
                    Text(model.iosBackgroundRefreshStatusLabel ?? "Unavailable")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityIDs.iosBackgroundRefreshStatusLabel)
                })
                .font(.caption)
            }

            if let backgroundRefreshDetail = model.iosBackgroundRefreshDetail {
                sectionDivider
                infoMessageRow(
                    backgroundRefreshDetail,
                    timestamp: nil,
                    accessibilityID: AccessibilityIDs.iosBackgroundRefreshDetailLabel
                )
            }

            #if DEBUG
            sectionDivider
            sectionRow {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await model.runIOSBackgroundRefreshVerificationNow()
                        }
                    } label: {
                        Label("Run Refresh Path Now", systemImage: "bolt.badge.clock")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canRunIOSBackgroundRefreshVerification)
                    .accessibilityIdentifier(AccessibilityIDs.iosBackgroundRefreshRunNowButton)

                    Spacer()
                }
                .font(.caption)
            }
            #endif
            #endif

            sectionDivider
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
                    .frame(
                        maxWidth: usesCompactMobileLayout ? .infinity : nil,
                        alignment: .trailing
                    )
                })
                .font(.caption)
            }
        }
    }

    private var bookingActionButtons: some View {
        Group {
            Button {
                _ = model.createBookingSiteBuild()
                bookingWorkspaceSection = .publish
                isBookingSettingsPresented = true
            } label: {
                Label(BookingCopy.Action.generatePageFiles, systemImage: BookingIconography.pageStep.primarySystemName)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRunBookingDryRun)
            .accessibilityIdentifier(AccessibilityIDs.bookingPublishButton)

            Button {
                Task {
                    await model.checkBookingInbox()
                }
            } label: {
                Label(BookingCopy.Action.checkInbox, systemImage: BookingIconography.checkInbox.primarySystemName)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canCheckBookingInbox)
            .accessibilityIdentifier(AccessibilityIDs.bookingCheckInboxButton)

            Button {
                Task {
                    await model.sendBookingTestRequest()
                }
            } label: {
                Label(BookingCopy.Action.sendTestRequest, systemImage: BookingIconography.testStep.primarySystemName)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canSendBookingTestRequest)
            .accessibilityIdentifier(AccessibilityIDs.bookingSendTestRequestButton)

            Button {
                Task {
                    await model.importBookingRequests()
                }
            } label: {
                Label(BookingCopy.Action.importRequests, systemImage: BookingIconography.requests.primarySystemName)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canImportBookingRequests)
            .accessibilityIdentifier(AccessibilityIDs.bookingImportRequestsButton)
        }
    }

    private func bookingRequestList(
        _ requests: [BookingImportedRequest],
        allowsActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(requests) { request in
                VStack(alignment: .leading, spacing: 8) {
                    adaptiveTrailingRow(label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(request.visitorDisplayName)
                                .fontWeight(.medium)
                            Text("\(request.plaintext.visitor.email) • \(request.status.label)")
                                .foregroundStyle(.secondary)
                            Text(request.topicPreview)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }, trailing: {
                        Group {
                            if allowsActions {
                                HStack(spacing: 8) {
                                    Button {
                                        Task {
                                            await model.approveBookingRequest(request.id)
                                        }
                                    } label: {
                                        Label("Approve", systemImage: "checkmark.circle")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!request.canApprove || model.isBookingApprovalInFlight)
                                    .accessibilityIdentifier(AccessibilityIDs.bookingApproveRequestButton(request.id.rawValue))

                                    Button(role: .destructive) {
                                        Task {
                                            await model.declineBookingRequest(request.id)
                                        }
                                    } label: {
                                        Label("Decline", systemImage: "xmark.circle")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!request.canDecline || model.isBookingApprovalInFlight)
                                    .accessibilityIdentifier(AccessibilityIDs.bookingDeclineRequestButton(request.id.rawValue))
                                }
                            } else {
                                Text(request.status.label)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    })
                    Text(request.message)
                        .font(.caption)
                        .foregroundStyle(request.status == .failed || request.status == .unavailable ? .red : .secondary)
                }
                .font(.caption)
                .padding(.vertical, 4)
            }
        }
    }

    private var bookingPageStatusRow: some View {
        sectionRow {
            VStack(alignment: .leading, spacing: 10) {
                adaptiveTrailingRow(label: {
                    Label(
                        BookingCopy.StatusCard.bookingPageTitle,
                        systemImage: BookingIconography.bookingPage.primarySystemName
                    )
                    .foregroundStyle(.secondary)
                }, trailing: {
                    HStack(spacing: 8) {
                        Text(model.bookingPageStatusLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(AccessibilityIDs.bookingPageStatusLabel)

                        Button {
                            guard let url = model.selectedBookingAppointmentTypeURL else { return }
                            openURL(url)
                        } label: {
                            Label(BookingCopy.Action.openBookingPage, systemImage: BookingIconography.openBookingPage.primarySystemName)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .disabled(!model.canUseSelectedBookingAppointmentTypeURL)
                        .accessibilityIdentifier(AccessibilityIDs.bookingOpenPageButton)
                        .accessibilityLabel(BookingCopy.Action.openBookingPage)

                        Button {
                            copyBookingPageURL()
                        } label: {
                            Label(BookingCopy.Action.copyBookingLink, systemImage: BookingIconography.copyBookingLink.primarySystemName)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .disabled(!model.canUseSelectedBookingAppointmentTypeURL)
                        .accessibilityIdentifier(AccessibilityIDs.bookingCopyPageURLButton)
                        .accessibilityLabel(BookingCopy.Action.copyBookingLink)
                    }
                })

                Picker(BookingCopy.Field.appointmentType, selection: $model.selectedBookingAppointmentTypeIDString) {
                    ForEach(model.bookingAppointmentTypes) { appointmentType in
                        Text(appointmentType.isPaused ? "\(appointmentType.name) (paused)" : appointmentType.name)
                            .tag(appointmentType.id.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.bookingAppointmentTypes.isEmpty)
                .accessibilityIdentifier(AccessibilityIDs.bookingAppointmentTypePicker)

                if !model.bookingPageEvidenceLines.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(model.bookingPageEvidenceLines, id: \.self) { line in
                            Label(line, systemImage: "number")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }
            }
            .font(.caption)
        }
    }

    private func bookingAppointmentStatusBadge(_ status: BookingAppointmentTypeLifecycleStatus) -> some View {
        let tint: Color = {
            switch status {
            case .live:
                return .green
            case .changedLocally:
                return .orange
            case .paused:
                return .secondary
            case .broken:
                return .red
            case .draft, .noSlots:
                return .blue
            }
        }()

        return Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func bookingStatusRow(
        title: String,
        status: String,
        icon: String,
        accessibilityID: String
    ) -> some View {
        sectionRow {
            adaptiveTrailingRow(label: {
                Label(title, systemImage: icon)
                    .foregroundStyle(.secondary)
            }, trailing: {
                Text(status)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(accessibilityID)
            })
            .font(.caption)
        }
    }

    private func copyBookingPageURL() {
        let urlString = model.selectedBookingAppointmentTypeURLString
        guard !urlString.isEmpty else {
            return
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = urlString
#endif
}

    @ViewBuilder
    private var bookingWorkspaceMessage: some View {
        if let message = model.bookingSetupSnapshot.lastMessage {
            Label(message, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openLocalBookingPagePreview() {
        guard model.createBookingSiteBuild() else {
            return
        }

        let previewURL = model.bookingPageFilesFolderURL.appendingPathComponent("index.html")
        #if os(macOS)
        if !NSWorkspace.shared.open(previewURL) {
            openURL(previewURL)
        }
        #elseif os(iOS)
        openURL(previewURL)
        #endif
    }

    private func updateAppointmentType(
        _ id: AppointmentTypeID,
        mutate: (inout BookingAppointmentType) -> Void
    ) {
        guard var appointmentType = model.bookingAppointmentTypes.first(where: { $0.id == id }) else {
            return
        }
        mutate(&appointmentType)
        model.updateBookingAppointmentType(appointmentType, replacing: id)
    }

    private func saveAppointmentSlug(_ slug: String, for appointmentType: BookingAppointmentType) -> String? {
        var edited = appointmentType
        edited.slug = slug

        do {
            try BookingConfigurationValidator.validateAppointmentTypes(
                model.bookingAppointmentTypes.map { current in
                    current.id == appointmentType.id ? edited : current
                }
            )
        } catch {
            return error.localizedDescription
        }

        model.updateBookingAppointmentType(edited, replacing: appointmentType.id)
        return nil
    }

    private func appointmentStringBinding(
        _ id: AppointmentTypeID,
        _ keyPath: WritableKeyPath<BookingAppointmentType, String>
    ) -> Binding<String> {
        Binding(
            get: { model.bookingAppointmentTypes.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                updateAppointmentType(id) { appointmentType in
                    appointmentType[keyPath: keyPath] = value
                }
            }
        )
    }

    private func appointmentIntegerBinding(
        _ id: AppointmentTypeID,
        _ keyPath: WritableKeyPath<BookingAppointmentType, Int>
    ) -> Binding<Int> {
        Binding(
            get: { model.bookingAppointmentTypes.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { value in
                updateAppointmentType(id) { appointmentType in
                    appointmentType[keyPath: keyPath] = value
                }
            }
        )
    }

    private func appointmentBoolBinding(
        _ id: AppointmentTypeID,
        _ keyPath: WritableKeyPath<BookingAppointmentType, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { model.bookingAppointmentTypes.first(where: { $0.id == id })?[keyPath: keyPath] ?? false },
            set: { value in
                updateAppointmentType(id) { appointmentType in
                    appointmentType[keyPath: keyPath] = value
                }
            }
        )
    }

    private func appointmentLocationModeBinding(_ id: AppointmentTypeID) -> Binding<BookingAppointmentLocationMode> {
        Binding(
            get: { model.bookingAppointmentTypes.first(where: { $0.id == id })?.location.mode ?? .none },
            set: { value in
                updateAppointmentType(id) { appointmentType in
                    appointmentType.location.mode = value
                    if value == .googleMeet || value == .none {
                        appointmentType.location.details = ""
                    }
                }
            }
        )
    }

    private var bookingSettingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(BookingCopy.Settings.title)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismissBookingSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(BookingCopy.Settings.title, systemImage: BookingIconography.settings.primarySystemName)
                        .font(.title3.weight(.semibold))

            Text("Create appointment types, generate page files, publish links, and manage the request inbox from one place.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                    bookingWorkspaceSectionSelector

                    bookingWorkspaceContent
                        .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .accessibilityIdentifier(AccessibilityIDs.bookingSettingsSheet)
        }
        .task {
            await model.refreshBookingCalendarTargetOptions()
        }
        .confirmationDialog(
            "Deploy booking changes?",
            isPresented: $isBookingPublishConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Deploy Changes") {
                Task {
                    await model.publishBookingPageToGitHub()
                    isBookingSettingsPresented = false
                }
            }

            Button("Don't Deploy") {
                isBookingSettingsPresented = false
            }

            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("There are booking page changes that have not been published yet.")
        }
    }

    private func dismissBookingSettings() {
        if model.shouldConfirmBookingPublishOnDismiss {
            isBookingPublishConfirmationPresented = true
        } else {
            isBookingSettingsPresented = false
        }
    }

    private var bookingWorkspaceSectionSelector: some View {
        HStack(spacing: 0) {
            ForEach(BookingWorkspaceSection.allCases) { section in
                Button {
                    bookingWorkspaceSection = section
                } label: {
                    Text(section.label)
                        .font(.caption.weight(bookingWorkspaceSection == section ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background {
                            if bookingWorkspaceSection == section {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                            }
                        }
                        .foregroundStyle(bookingWorkspaceSection == section ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIDs.bookingWorkspaceSectionPicker)
    }

    @ViewBuilder
    private var bookingWorkspaceContent: some View {
        switch bookingWorkspaceSection {
        case .overview:
            bookingWorkspaceOverview
        case .appointmentTypes:
            bookingAppointmentTypesWorkspace
        case .pageFiles:
            bookingPageFilesWorkspace
        case .publish:
            bookingPublishWorkspace
        case .requestInbox:
            bookingRequestInboxWorkspace
        case .history:
            bookingHistoryWorkspace
        }
    }

    private var bookingWorkspaceOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.bookingSetupSnapshot.headline, systemImage: model.bookingSetupSnapshot.isReady ? BookingIconography.ready.primarySystemName : BookingIconography.incompleteSetup.primarySystemName)
                .font(.headline)
            Text(model.bookingSetupSnapshot.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            bookingReadinessChecklist
            bookingPageStatusRow
            Toggle(isOn: $model.isAutomaticBookingApprovalEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(BookingCopy.Action.automaticBookingApproval)
                    Text("Imported requests are accepted only after this app rechecks availability and writes to the appointment type's target calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier(AccessibilityIDs.bookingAutomaticApprovalToggle)
        }
    }

    private var bookingReadinessChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            bookingReadinessRow(
                title: "Appointment types",
                detail: model.hasActiveBookingAppointmentTypes ? "\(model.bookingAppointmentTypes.count) configured" : "Create or resume at least one appointment type",
                icon: "list.bullet.rectangle",
                isComplete: model.hasActiveBookingAppointmentTypes,
                actionTitle: "Edit",
                actionIcon: "pencil"
            ) {
                bookingWorkspaceSection = .appointmentTypes
            }
            bookingReadinessRow(
                title: "Public page",
                detail: model.bookingPageStatusLabel,
                icon: BookingIconography.bookingPage.primarySystemName,
                isComplete: model.bookingSetupSnapshot.pageStatus == .published,
                actionTitle: "Customize",
                actionIcon: "paintpalette"
            ) {
                bookingWorkspaceSection = .pageFiles
            }
            bookingReadinessRow(
                title: "Publish",
                detail: model.bookingPageEvidenceLines.first ?? "Generate, upload, then verify the live version",
                icon: BookingIconography.publishPage.primarySystemName,
                isComplete: model.bookingSetupSnapshot.pageStatus == .published,
                actionTitle: "Publish",
                actionIcon: "square.and.arrow.up"
            ) {
                bookingWorkspaceSection = .publish
            }
            bookingReadinessRow(
                title: "Request inbox",
                detail: model.bookingInboxStatusLabel,
                icon: BookingIconography.inbox.primarySystemName,
                isComplete: model.bookingSetupSnapshot.inboxStatus == .connected,
                actionTitle: "Connect",
                actionIcon: "tray"
            ) {
                bookingWorkspaceSection = .requestInbox
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func bookingReadinessRow(
        title: String,
        detail: String,
        icon: String,
        isComplete: Bool,
        actionTitle: String,
        actionIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        adaptiveTrailingRow(label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                    .foregroundStyle(isComplete ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        }, trailing: {
            Button(action: action) {
                Label(actionTitle, systemImage: actionIcon)
            }
            .buttonStyle(.bordered)
        })
        .font(.caption)
    }

    private var bookingAppointmentTypesWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isBookingAppointmentTypeDetailVisible, let appointmentType = model.selectedBookingAppointmentType {
                bookingAppointmentTypeDetailPage(appointmentType)
            } else {
            adaptiveTrailingRow(label: {
                Label("Appointment types", systemImage: "list.bullet.rectangle")
                    .font(.headline)
            }, trailing: {
                Button {
                    let appointmentType = model.addBookingAppointmentType()
                    model.selectedBookingAppointmentTypeIDString = appointmentType.id.rawValue
                    isBookingAppointmentTypeDetailVisible = true
                } label: {
                    Label("Add appointment type", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityIDs.bookingAddAppointmentTypeButton)
            })

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.bookingAppointmentTypes) { appointmentType in
                    bookingAppointmentTypeCard(appointmentType)
                }
            }
            }
        }
    }

    private func bookingAppointmentTypeCard(_ appointmentType: BookingAppointmentType) -> some View {
        let isSelected = model.selectedBookingAppointmentTypeIDString == appointmentType.id.rawValue
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(appointmentType.name)
                        .font(.headline)
                    bookingAppointmentStatusBadge(model.bookingAppointmentTypeLifecycleStatus(appointmentType))
                }
                Text(appointmentMetadataLine(appointmentType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appointmentHoursSummary(appointmentType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.bookingCalendarTargetSummary(for: appointmentType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let url = model.bookingPageURL(for: appointmentType) {
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        #elseif os(iOS)
                        UIPasteboard.general.string = url.absoluteString
                        #endif
                    } label: {
                        Label("Copy link", systemImage: "link")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openURL(url)
                    } label: {
                        Label("Open booking link", systemImage: "arrow.up.right.square")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Open booking link")
                }

                Menu {
                    if appointmentType.isPaused {
                        Button {
                            model.resumeBookingAppointmentType(appointmentType.id)
                        } label: {
                            Label("Resume", systemImage: "play.circle")
                        }
                    } else {
                        Button {
                            model.pauseBookingAppointmentType(appointmentType.id)
                        } label: {
                            Label("Pause", systemImage: "pause.circle")
                        }
                    }

                    Button {
                        if let copy = model.duplicateBookingAppointmentType(appointmentType.id) {
                            model.selectedBookingAppointmentTypeIDString = copy.id.rawValue
                        }
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }

                    Button(role: .destructive) {
                        model.deleteBookingAppointmentType(appointmentType.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(model.bookingAppointmentTypes.count <= 1)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More actions")
            }
            .font(.caption)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedBookingAppointmentTypeIDString = appointmentType.id.rawValue
            isBookingAppointmentTypeDetailVisible = true
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.07) : Color.secondary.opacity(0.06))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(appointmentType.isPaused ? Color.secondary : (isSelected ? Color.blue : Color.purple))
                .frame(width: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.35) : Color.secondary.opacity(0.18))
        }
    }

    private func bookingAppointmentTypeDetailPage(_ appointmentType: BookingAppointmentType) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            adaptiveTrailingRow(label: {
                Button {
                    isBookingAppointmentTypeDetailVisible = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }, trailing: {
                HStack(spacing: 8) {
                    if let url = model.bookingPageURL(for: appointmentType) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open booking link", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                    }

                    Menu {
                        if appointmentType.isPaused {
                            Button {
                                model.resumeBookingAppointmentType(appointmentType.id)
                            } label: {
                                Label("Resume", systemImage: "play.circle")
                            }
                        } else {
                            Button {
                                model.pauseBookingAppointmentType(appointmentType.id)
                            } label: {
                                Label("Pause", systemImage: "pause.circle")
                            }
                        }

                        Button {
                            if let copy = model.duplicateBookingAppointmentType(appointmentType.id) {
                                model.selectedBookingAppointmentTypeIDString = copy.id.rawValue
                            }
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }

                        Button(role: .destructive) {
                            model.deleteBookingAppointmentType(appointmentType.id)
                            isBookingAppointmentTypeDetailVisible = false
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(model.bookingAppointmentTypes.count <= 1)
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .buttonStyle(.bordered)
                }
            })

            VStack(alignment: .leading, spacing: 4) {
                Text(appointmentType.name)
                    .font(.title3.weight(.semibold))
                Text(appointmentMetadataLine(appointmentType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            bookingAppointmentTypeEditor(appointmentType)
        }
    }

    private func bookingAppointmentTypeEditor(_ appointmentType: BookingAppointmentType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Event type", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(BookingCopy.Field.appointmentName, text: appointmentStringBinding(appointmentType.id, \.name))
                    .textFieldStyle(.roundedBorder)

                BookingAppointmentSlugField(slug: appointmentType.slug) { slug in
                    saveAppointmentSlug(slug, for: appointmentType)
                }
                Text("Changing the link name updates future share links, but the appointment ID and request history stay stable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Summary", text: appointmentStringBinding(appointmentType.id, \.summary), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            .padding(16)

            Divider()

            bookingDisclosureSection(
                title: BookingCopy.Field.duration,
                value: durationLabel(appointmentType.durationMinutes),
                isExpanded: $isBookingDurationSectionExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    appointmentDurationPicker(
                        title: BookingCopy.Field.duration,
                        value: appointmentIntegerBinding(appointmentType.id, \.durationMinutes),
                        values: [15, 30, 45, 60, 90],
                        suffix: "min"
                    )
                    appointmentDurationPicker(
                        title: BookingCopy.Field.minimumNotice,
                        value: appointmentIntegerBinding(appointmentType.id, \.minimumNoticeMinutes),
                        values: [0, 60, 240, 1_440, 2_880],
                        suffix: "min"
                    )
                    appointmentDurationPicker(
                        title: BookingCopy.Field.bufferBefore,
                        value: appointmentIntegerBinding(appointmentType.id, \.bufferBeforeMinutes),
                        values: [0, 5, 10, 15, 30],
                        suffix: "min"
                    )
                    appointmentDurationPicker(
                        title: BookingCopy.Field.bufferAfter,
                        value: appointmentIntegerBinding(appointmentType.id, \.bufferAfterMinutes),
                        values: [0, 5, 10, 15, 30],
                        suffix: "min"
                    )
                }
                .padding(.top, 10)
            }
            .padding(16)

            Divider()

            bookingAppointmentTargetSection(appointmentType)
                .padding(16)

            Divider()

            bookingDisclosureSection(
                title: BookingCopy.Field.location,
                value: locationLabel(appointmentType.location.mode),
                isExpanded: $isBookingLocationSectionExpanded
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(BookingCopy.Field.location, selection: appointmentLocationModeBinding(appointmentType.id)) {
                        ForEach(BookingAppointmentLocationMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if appointmentType.location.mode == .googleMeet && !model.canCreateGoogleMeet(for: appointmentType) {
                        Label("Choose a Google calendar before creating Google Meet links.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 10)
            }
            .padding(16)

            Divider()

            bookingDisclosureSection(
                title: "Availability",
                value: "\(availabilityHorizonLabel(appointmentType.availabilityHorizonDays)), \(appointmentHoursSummary(appointmentType))",
                isExpanded: $isBookingAvailabilitySectionExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    appointmentAvailabilityHorizonPicker(
                        value: appointmentIntegerBinding(appointmentType.id, \.availabilityHorizonDays)
                    )
                    bookingWeeklyHoursEditor(appointmentType)
                }
                .padding(.top, 10)
            }
            .padding(16)

            Divider()

            Toggle(isOn: appointmentBoolBinding(appointmentType.id, \.isAutoConfirmEnabled)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatically accept this appointment type")
                    Text("Accepted only after this app rechecks availability and writes the calendar event.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(16)
        }
        .font(.caption)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18))
        }
    }

    private func bookingAppointmentTargetSection(_ appointmentType: BookingAppointmentType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Target calendar", systemImage: "calendar.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(model.bookingCalendarTargetSummary(for: appointmentType))
                .font(.subheadline.weight(.semibold))
            Text(model.bookingCalendarTargetDetail(for: appointmentType))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.bookingCalendarTargetOptions.isEmpty {
                if let warning = model.bookingCalendarTargetWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Picker(
                    "Target calendar",
                    selection: Binding(
                        get: { model.selectedBookingCalendarTargetOptionID(for: appointmentType.id) },
                        set: { model.setBookingCalendarTargetOptionID($0, for: appointmentType.id) }
                    )
                ) {
                    Text("Choose a target calendar").tag("")
                    ForEach(model.bookingCalendarTargetOptions) { option in
                        Text("\(option.label) - \(option.detail)").tag(option.id)
                    }
                }
                .pickerStyle(.menu)
            }

            ViewThatFits {
                HStack(spacing: 10) {
                    bookingTargetActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    bookingTargetActions
                }
            }
        }
    }

    private func bookingDisclosureSection<Content: View>(
        title: String,
        value: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let value {
                            Text(value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func appointmentDurationPicker(
        title: String,
        value: Binding<Int>,
        values: [Int],
        suffix: String
    ) -> some View {
        adaptiveTrailingRow(label: {
            Text(title)
                .fontWeight(.medium)
        }, trailing: {
            Picker(title, selection: value) {
                ForEach(normalizedMenuValues(current: value.wrappedValue, values: values), id: \.self) { option in
                    Text(durationLabel(option, suffix: suffix)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 140, alignment: .trailing)
        })
    }

    private func appointmentAvailabilityHorizonPicker(value: Binding<Int>) -> some View {
        adaptiveTrailingRow(label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show availability")
                    .fontWeight(.medium)
                Text("Published again on every poll so the booking page stays current.")
                    .foregroundStyle(.secondary)
            }
        }, trailing: {
            Picker("Show availability", selection: value) {
                ForEach(normalizedMenuValues(current: value.wrappedValue, values: [7, 14, 30, 60, 90]), id: \.self) { days in
                    Text(availabilityHorizonLabel(days)).tag(days)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 150, alignment: .trailing)
        })
    }

    private func bookingWeeklyHoursEditor(_ appointmentType: BookingAppointmentType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly hours")
                    .font(.subheadline.weight(.semibold))
                Text("Set when this appointment type is usually available.")
                    .foregroundStyle(.secondary)
            }

            ForEach(1...7, id: \.self) { weekday in
                bookingWeeklyHoursDayRow(appointmentType, weekday: weekday)
            }
        }
    }

    private func bookingWeeklyHoursDayRow(
        _ appointmentType: BookingAppointmentType,
        weekday: Int
    ) -> some View {
        let windows = appointmentType.weeklyHours.first { $0.weekday == weekday }?.windows ?? []
        return HStack(alignment: .top, spacing: 12) {
            Text(shortWeekdayLabel(weekday))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary))

            if windows.isEmpty {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
                Button {
                    addBookingWeeklyWindow(appointmentType.id, weekday: weekday)
                } label: {
                    Label("Add hours", systemImage: "plus.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                        bookingWeeklyWindowRow(
                            appointmentType,
                            weekday: weekday,
                            windowIndex: index,
                            window: window
                        )
                    }
                }
            }
        }
    }

    private func bookingWeeklyWindowRow(
        _ appointmentType: BookingAppointmentType,
        weekday: Int,
        windowIndex: Int,
        window: BookingWorkingHours
    ) -> some View {
        HStack(spacing: 8) {
            bookingTimePicker(
                minute: window.startMinuteOfDay,
                label: "Start time",
                values: bookingStartTimeValues
            ) { newValue in
                updateBookingWeeklyWindow(appointmentType.id, weekday: weekday, windowIndex: windowIndex) { edited in
                    edited.startMinuteOfDay = min(newValue, edited.endMinuteOfDay - 15)
                }
            }

            Text("-")
                .foregroundStyle(.secondary)

            bookingTimePicker(
                minute: window.endMinuteOfDay,
                label: "End time",
                values: bookingEndTimeValues
            ) { newValue in
                updateBookingWeeklyWindow(appointmentType.id, weekday: weekday, windowIndex: windowIndex) { edited in
                    edited.endMinuteOfDay = max(newValue, edited.startMinuteOfDay + 15)
                }
            }

            Spacer(minLength: 0)

            Button {
                removeBookingWeeklyWindow(appointmentType.id, weekday: weekday, windowIndex: windowIndex)
            } label: {
                Label("Remove hours", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)

            Button {
                addBookingWeeklyWindow(appointmentType.id, weekday: weekday)
            } label: {
                Label("Add hours", systemImage: "plus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
    }

    private func bookingTimePicker(
        minute: Int,
        label: String,
        values: [Int],
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Picker(label, selection: Binding(
            get: { minute },
            set: { onChange($0) }
        )) {
            ForEach(normalizedMenuValues(current: minute, values: values), id: \.self) { value in
                Text(timeLabel(value)).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 115)
    }

    private func appointmentMetadataLine(_ appointmentType: BookingAppointmentType) -> String {
        [
            durationLabel(appointmentType.durationMinutes),
            availabilityHorizonLabel(appointmentType.availabilityHorizonDays),
            locationLabel(appointmentType.location.mode),
            "One-on-One",
        ].joined(separator: " • ")
    }

    private func appointmentHoursSummary(_ appointmentType: BookingAppointmentType) -> String {
        let openDays = appointmentType.weeklyHours
            .filter { !$0.windows.isEmpty }
            .sorted { $0.weekday < $1.weekday }

        guard !openDays.isEmpty else {
            return "No weekly hours"
        }

        let dayLabel: String
        if openDays.map(\.weekday) == [2, 3, 4, 5, 6] {
            dayLabel = "Weekdays"
        } else {
            dayLabel = openDays.map { shortWeekdayLabel($0.weekday) }.joined(separator: ", ")
        }

        let uniqueWindows = Set(openDays.flatMap { day in
            day.windows.map { "\($0.startMinuteOfDay)-\($0.endMinuteOfDay)" }
        })
        if uniqueWindows.count == 1, let firstWindow = openDays.first?.windows.first {
            return "\(dayLabel), \(timeLabel(firstWindow.startMinuteOfDay)) - \(timeLabel(firstWindow.endMinuteOfDay))"
        }

        return "\(dayLabel), custom hours"
    }

    private func locationLabel(_ mode: BookingAppointmentLocationMode) -> String {
        switch mode {
        case .googleMeet:
            return "Google Meet"
        case .none:
            return "No location"
        case .custom:
            return "Custom location"
        case .phone:
            return "Phone call"
        }
    }

    private func durationLabel(_ minutes: Int, suffix: String = "min") -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }
        if minutes > 60 {
            return "\(minutes / 60) hr \(minutes % 60) min"
        }
        return "\(minutes) \(suffix)"
    }

    private func availabilityHorizonLabel(_ days: Int) -> String {
        switch days {
        case 7:
            return "1 week"
        case 14:
            return "2 weeks"
        case 30:
            return "1 month"
        case 60:
            return "2 months"
        case 90:
            return "3 months"
        default:
            return "\(days) days"
        }
    }

    private var bookingStartTimeValues: [Int] {
        Array(stride(from: 0, through: (24 * 60) - 15, by: 15))
    }

    private var bookingEndTimeValues: [Int] {
        Array(stride(from: 15, through: 24 * 60, by: 15))
    }

    private func timeLabel(_ minute: Int) -> String {
        let clampedMinute = max(0, min(24 * 60, minute))
        if clampedMinute == 24 * 60 {
            return "12:00am"
        }

        let hour = clampedMinute / 60
        let minutes = clampedMinute % 60
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "am" : "pm"
        return minutes == 0
            ? "\(displayHour):00\(period)"
            : "\(displayHour):\(String(format: "%02d", minutes))\(period)"
    }

    private func shortWeekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1:
            return "S"
        case 2:
            return "M"
        case 3:
            return "T"
        case 4:
            return "W"
        case 5:
            return "T"
        case 6:
            return "F"
        case 7:
            return "S"
        default:
            return "?"
        }
    }

    private func normalizedMenuValues(current: Int, values: [Int]) -> [Int] {
        Array(Set(values + [current])).sorted()
    }

    private func addBookingWeeklyWindow(_ id: AppointmentTypeID, weekday: Int) {
        updateBookingWeeklyHours(id, weekday: weekday) { windows in
            windows.append(.weekdayDefault)
        }
    }

    private func removeBookingWeeklyWindow(
        _ id: AppointmentTypeID,
        weekday: Int,
        windowIndex: Int
    ) {
        updateBookingWeeklyHours(id, weekday: weekday) { windows in
            guard windows.indices.contains(windowIndex) else {
                return
            }
            windows.remove(at: windowIndex)
        }
    }

    private func updateBookingWeeklyWindow(
        _ id: AppointmentTypeID,
        weekday: Int,
        windowIndex: Int,
        update: (inout BookingWorkingHours) -> Void
    ) {
        updateBookingWeeklyHours(id, weekday: weekday) { windows in
            guard windows.indices.contains(windowIndex) else {
                return
            }
            update(&windows[windowIndex])
        }
    }

    private func updateBookingWeeklyHours(
        _ id: AppointmentTypeID,
        weekday: Int,
        update: (inout [BookingWorkingHours]) -> Void
    ) {
        updateAppointmentType(id) { appointmentType in
            var weeklyHours = appointmentType.weeklyHours
            if let dayIndex = weeklyHours.firstIndex(where: { $0.weekday == weekday }) {
                update(&weeklyHours[dayIndex].windows)
            } else {
                var windows: [BookingWorkingHours] = []
                update(&windows)
                weeklyHours.append(BookingWeeklyHours(weekday: weekday, windows: windows))
            }

            weeklyHours = weeklyHours
                .map { day in
                    BookingWeeklyHours(
                        weekday: day.weekday,
                        windows: day.windows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
                    )
                }
                .sorted { $0.weekday < $1.weekday }

            guard (try? BookingConfigurationValidator.validateWeeklyHours(weeklyHours)) != nil else {
                return
            }

            appointmentType.weeklyHours = weeklyHours
        }
    }

    private var bookingPageFilesWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Public Page", systemImage: "paintpalette")
                .font(.headline)
            Text("Customize public copy and styling, preview locally, then regenerate the files that GitHub Pages serves.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Page profile", systemImage: "person.text.rectangle")
                    .font(.caption.weight(.semibold))
                TextField("Public name", text: $model.bookingPublicNameString)
                    .textFieldStyle(.roundedBorder)
                TextField("Page title", text: $model.bookingPageTitleString)
                    .textFieldStyle(.roundedBorder)
                TextField("Subtitle", text: $model.bookingPageSubtitleString, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                TextField("Time zone", text: $model.bookingTimeZoneIdentifierString)
                    .textFieldStyle(.roundedBorder)
                Text(model.bookingPagePreviewSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                Label("Theme", systemImage: "swatchpalette")
                    .font(.caption.weight(.semibold))
                ViewThatFits {
                    HStack(spacing: 10) {
                        bookingThemeField("Accent", text: $model.bookingThemeAccentColorString)
                        bookingThemeField("Background", text: $model.bookingThemeBackgroundColorString)
                        bookingThemeField("Text", text: $model.bookingThemeTextColorString)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        bookingThemeField("Accent", text: $model.bookingThemeAccentColorString)
                        bookingThemeField("Background", text: $model.bookingThemeBackgroundColorString)
                        bookingThemeField("Text", text: $model.bookingThemeTextColorString)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Label("Safety check", systemImage: "checkmark.shield")
                    .font(.caption.weight(.semibold))
                ForEach(model.bookingPageSafetyLines, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            bookingDisclosureSection(
                title: "Customization boundaries",
                isExpanded: $isBookingCustomizationBoundariesExpanded
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit these files in the app's template folder, then generate page files to preview or publish.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.bookingPageTemplateFolderPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                    Label("Safe customization files", systemImage: "checkmark.shield")
                        .font(.caption.weight(.semibold))
                    ForEach(model.bookingSafeCustomizationFileLines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }

                    Divider()

                    Label("Protected protocol files", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    ForEach(model.bookingProtectedProtocolFileLines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 8)
            }

            Text("Generated page files")
                .font(.caption.weight(.semibold))
            Text(model.bookingPageFilesFolderPath)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

            bookingWorkspaceMessage

            ViewThatFits {
                HStack(spacing: 10) {
                    bookingPageFileButtons
                }
                VStack(alignment: .leading, spacing: 10) {
                    bookingPageFileButtons
                }
            }
            .font(.caption)
        }
    }

    private var bookingPageFileButtons: some View {
        Group {
            bookingGeneratePageFilesButton(
                title: "Generate page files",
                systemImage: "doc.text",
                isProminent: model.bookingSetupSnapshot.shouldEmphasizePageGeneration
            )

            Button {
                _ = model.createBookingSiteBuild()
            } label: {
                Label("Run safety check", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)

            Button {
                openLocalBookingPagePreview()
            } label: {
                Label("Preview local page", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            #if os(macOS)
            Button {
                if model.prepareBookingPageTemplateFolder() {
                    NSWorkspace.shared.open(model.bookingPageTemplateFolderURL)
                }
            } label: {
                Label("Open template folder", systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.bordered)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([model.bookingPageFilesFolderURL])
            } label: {
                Label("Open generated files", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            #endif
        }
    }

    @ViewBuilder
    private func bookingGeneratePageFilesButton(
        title: String,
        systemImage: String,
        isProminent: Bool
    ) -> some View {
        if isProminent {
            Button {
                _ = model.createBookingSiteBuild()
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                _ = model.createBookingSiteBuild()
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
    }

    private func bookingThemeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            TextField("#000000", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
        }
    }

    private var bookingPublishWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Publish", systemImage: BookingIconography.publishPage.primarySystemName)
                .font(.headline)
            Text("Publish generated static files to the root of an empty GitHub Pages repository. The app stores the private deploy key in secure storage and shows the public key for GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(BookingCopy.Field.githubRepository, text: $model.bookingGitHubRepositoryString)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIDs.bookingGitHubRepositoryField)

            TextField("Branch", text: $model.bookingGitHubBranchString)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Label("Deploy key", systemImage: "key.horizontal")
                    .font(.caption.weight(.semibold))
                Text(model.bookingGitHubDeployKeyStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.bookingGitHubDeployKeyFingerprintString.isEmpty {
                    Text(model.bookingGitHubDeployKeyFingerprintString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !model.bookingGitHubDeployKeyPublicKeyString.isEmpty {
                    Text(model.bookingGitHubDeployKeyPublicKeyString)
                        .font(.caption.monospaced())
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(AccessibilityIDs.bookingGitHubDeployKeyPublicKey)
                }
                ViewThatFits {
                    HStack(spacing: 8) {
                        bookingDeployKeyActions
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        bookingDeployKeyActions
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            if model.canUseInferredBookingPageURL {
                adaptiveTrailingRow(label: {
                    Text(model.inferredBookingPageURLString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }, trailing: {
                    Button {
                        model.useInferredGitHubPagesURL()
                    } label: {
                        Label("Use URL", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                })
            }

            TextField(BookingCopy.Field.bookingPageURL, text: $model.bookingPageURLString)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIDs.bookingPageURLField)

            VStack(alignment: .leading, spacing: 8) {
                Label("Publication evidence", systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                if model.bookingPageEvidenceLines.isEmpty {
                    Text("Generate files, upload to GitHub, then verify the served fingerprint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.bookingPageEvidenceLines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Text("GitHub Pages can lag after upload; keep this state as Uploaded until verification sees the matching fingerprint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            bookingWorkspaceMessage

            ViewThatFits {
                HStack(spacing: 10) {
                    bookingPublishActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    bookingPublishActions
                }
            }
            .font(.caption)
        }
    }

    private var bookingPublishActions: some View {
        Group {
            bookingGeneratePageFilesButton(
                title: BookingCopy.Action.runDryRun,
                systemImage: BookingIconography.pageStep.primarySystemName,
                isProminent: false
            )
            bookingPublishPageButton
            bookingVerifyLivePageButton
        }
    }

    private var bookingDeployKeyActions: some View {
        Group {
            Button {
                Task {
                    await model.generateBookingGitHubDeployKey()
                }
            } label: {
                Label(BookingCopy.Action.generateDeployKey, systemImage: "key")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canGenerateBookingGitHubDeployKey)

            Button {
                copyBookingGitHubDeployKey()
            } label: {
                Label(BookingCopy.Action.copyDeployKey, systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(model.bookingGitHubDeployKeyPublicKeyString.isEmpty)

            Button {
                Task {
                    await model.verifyBookingGitHubDeployKey()
                }
            } label: {
                Label(BookingCopy.Action.verifyDeployKey, systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .disabled(!model.hasMatchingBookingGitHubDeployKey)
        }
    }

    private func copyBookingGitHubDeployKey() {
        let publicKey = model.bookingGitHubDeployKeyPublicKeyString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty else { return }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(publicKey, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = publicKey
        #endif
    }

    @ViewBuilder
    private var bookingPublishPageButton: some View {
        let isProminent = model.bookingSetupSnapshot.shouldEmphasizePublish && model.canPublishBookingPageToGitHub
        if isProminent {
            Button {
                Task {
                    await model.publishBookingPageToGitHub()
                }
            } label: {
                Label(BookingCopy.Action.publishPage, systemImage: BookingIconography.publishPage.primarySystemName)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canPublishBookingPageToGitHub)
            .accessibilityIdentifier(AccessibilityIDs.bookingPublishButton)
        } else {
            Button {
                Task {
                    await model.publishBookingPageToGitHub()
                }
            } label: {
                Label(BookingCopy.Action.publishPage, systemImage: BookingIconography.publishPage.primarySystemName)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canPublishBookingPageToGitHub)
            .accessibilityIdentifier(AccessibilityIDs.bookingPublishButton)
        }
    }

    @ViewBuilder
    private var bookingVerifyLivePageButton: some View {
        let isProminent = model.bookingSetupSnapshot.shouldEmphasizeVerification && model.canVerifyBookingPage
        if isProminent {
            Button {
                Task {
                    await model.verifyBookingPagePublished()
                }
            } label: {
                Label("Verify live page", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canVerifyBookingPage)
        } else {
            Button {
                Task {
                    await model.verifyBookingPagePublished()
                }
            } label: {
                Label("Verify live page", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canVerifyBookingPage)
        }
    }

    private var bookingRequestInboxWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(BookingCopy.StatusCard.inboxTitle, systemImage: BookingIconography.inbox.primarySystemName)
                .font(.headline)
            Text("The request inbox stores encrypted requests until this app reads them. Private booking keys stay in Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Inbox setup mode", selection: $bookingInboxSetupMode) {
                ForEach(BookingInboxSetupMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField(BookingCopy.Field.inboxURL, text: $model.bookingInboxURLString)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIDs.bookingInboxURLField)
            SecureField(BookingCopy.Field.inboxAdminToken, text: $model.bookingInboxAdminTokenString)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIDs.bookingInboxAdminTokenField)

            if bookingInboxSetupMode == .vercel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Guided Vercel deploy", systemImage: "shippingbox")
                        .font(.caption.weight(.semibold))
                    TextField("Vercel team or account (optional)", text: $model.bookingVercelScopeString)
                        .textFieldStyle(.roundedBorder)
                    TextField("Vercel project", text: $model.bookingVercelProjectNameString)
                        .textFieldStyle(.roundedBorder)
                    Text("Deploy the Vercel relay template, set production environment variables, paste the production URL here, then run Check inbox. The team/account field is only needed when a Vercel CLI deploy must target a specific team.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.bookingVercelEnvironmentLines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Inbox evidence", systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                ForEach(model.bookingRequestInboxEvidenceLines, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Check inbox verifies /healthz. When health reports an allowed origin, it must match the GitHub Pages origin before the inbox is Ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            bookingActionButtons
                .font(.caption)
        }
    }

    private var bookingHistoryWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if model.hasBookingRequestHistory {
                bookingRequestList(model.bookingRequestHistory, allowsActions: false)
            } else {
                Text(BookingCopy.StatusCard.noBookingRequests)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bookingTargetActions: some View {
        Group {
            Button {
                Task {
                    await model.refreshBookingCalendarTargetOptions()
                }
            } label: {
                Label("Refresh calendars", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

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

            Button {
                Task {
                    await model.connectGoogleAccount()
                }
            } label: {
                Label(model.googleConnectButtonTitle, systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canStartGoogleSignIn)
            .accessibilityIdentifier(AccessibilityIDs.googleAuthConnectButton)
        }
    }

    private var bookingHistorySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Request history", systemImage: "clock.arrow.circlepath")
                        .font(.title3.weight(.semibold))

                    if model.hasBookingRequestHistory {
                        bookingRequestList(model.bookingRequestHistory, allowsActions: false)
                    } else {
                        Text(BookingCopy.StatusCard.noBookingRequests)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .topLeading)
            }
            .accessibilityIdentifier(AccessibilityIDs.bookingRequestHistorySheet)
            .navigationTitle("Request history")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isBookingHistoryPresented = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func googleAccountRow(_ row: GoogleAccountRosterRowModel) -> some View {
        switch row.kind {
        case .connected:
            if let localCard = row.localCard {
                connectedGoogleAccountRow(localCard)
            }
        case .needsLocalConnection:
            sharedGoogleAccountConnectRow(row)
        case .removedFromShared:
            removedSharedGoogleAccountRow(row)
        }
    }

    private func connectedGoogleAccountRow(_ card: GoogleAccountCardModel) -> some View {
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
                    calendarLabelRow {
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
                .font(calendarControlFont)
            } else {
                adaptiveTrailingRow(label: {
                    calendarLabelRow {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(calendarControlFont)
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

    private func sharedGoogleAccountConnectRow(_ row: GoogleAccountRosterRowModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            adaptiveTrailingRow(label: {
                accountIdentityRow(
                    title: row.displayName,
                    subtitle: row.email
                )
                .accessibilityIdentifier(AccessibilityIDs.googleAccountCard(row.stableAccountID))
            }, trailing: {
                Button {
                    Task {
                        await model.connectSharedGoogleAccount(row.stableAccountID)
                    }
                } label: {
                    Label("Connect Here", systemImage: "link.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canStartGoogleSignIn)
                .accessibilityIdentifier(AccessibilityIDs.googleAuthConnectSharedButton(row.stableAccountID))
            })
            .font(.caption)

            adaptiveTrailingRow(label: {
                calendarLabelRow {
                    Text(row.selectedCalendarDisplayName ?? "Will use the shared calendar selection after sign-in.")
                        .foregroundStyle(.secondary)
                }
            }, trailing: {
                Text("Shared setup")
                    .foregroundStyle(.secondary)
            })
            .font(calendarControlFont)

            infoMessageRow(
                "This Google account was configured on another device. Connect it here to reuse the same calendar settings on this device.",
                timestamp: nil,
                accessibilityID: AccessibilityIDs.googleCalendarMessageLabel(row.stableAccountID)
            )
        }
    }

    private func removedSharedGoogleAccountRow(_ row: GoogleAccountRosterRowModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            adaptiveTrailingRow(label: {
                accountIdentityRow(
                    title: row.displayName,
                    subtitle: row.email
                )
                .accessibilityIdentifier(AccessibilityIDs.googleAccountCard(row.stableAccountID))
            }, trailing: {
                Button(role: .destructive) {
                    model.removeGoogleAccount(row.stableAccountID)
                } label: {
                    Label("Remove Here", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(model.isGoogleAuthInFlight)
                .accessibilityIdentifier(AccessibilityIDs.googleAuthRemoveSharedButton(row.stableAccountID))
            })
            .font(.caption)

            infoMessageRow(
                "This account was removed from shared settings on another device. Remove it here to keep this device aligned.",
                timestamp: nil,
                accessibilityID: AccessibilityIDs.googleCalendarMessageLabel(row.stableAccountID)
            )
        }
    }

    private var appleCalendarSelectionRow: some View {
        Group {
            if model.appleCalendars.isEmpty {
                adaptiveTrailingRow(label: {
                    calendarLabelRow {
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
                .font(calendarControlFont)
            } else {
                adaptiveTrailingRow(label: {
                    calendarLabelRow {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(calendarControlFont)
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
            HStack(spacing: 6) {
                Image(systemName: model.currentActivityIconName)
                Text(model.currentActivitySummary)
                    .fontWeight(.medium)
                if let timestampSuffix = model.currentActivityTimestampSuffix {
                    Text(timestampSuffix)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
                .accessibilityIdentifier(AccessibilityIDs.syncStatusDetail)

            Spacer(minLength: 8)

            if usesCompactMobileLayout {
                mobileStatusOverflowButton
            } else {
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .sheet(isPresented: $isMobileStatusSheetPresented) {
            #if os(iOS)
            mobileStatusSheet
            #endif
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

    private var addGoogleAccountButtonTitle: String {
        usesCompactMobileLayout ? "Add" : "Add Google Account"
    }

    private var scrollContentBottomPadding: CGFloat {
        usesCompactMobileLayout ? 104 : 28
    }

    private var calendarControlFont: Font {
        usesCompactMobileLayout ? .caption2 : .caption
    }

    @ViewBuilder
    private var calendarLabel: some View {
        if usesCompactMobileLayout {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
        } else {
            Label("Calendar", systemImage: "calendar")
                .foregroundStyle(.secondary)
        }
    }

    private var usesCompactMobileLayout: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var mobileStatusOverflowBadgeText: String? {
        guard model.failureCount > 0 else {
            return nil
        }

        if model.failureCount > 99 {
            return "99+"
        }

        return String(model.failureCount)
    }

    private var mobileStatusOverflowButton: some View {
        Button {
            isMobileStatusSheetPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.headline)
                .frame(width: 30, height: 30)
                .overlay(alignment: .topTrailing) {
                    if let badgeText = mobileStatusOverflowBadgeText {
                        Text(badgeText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, badgeText.count > 2 ? 5 : 4)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier(AccessibilityIDs.syncStatusOverflowButton)
    }

    private func calendarLabelRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            calendarLabel
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(iOS)
    private var mobileStatusSheet: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Label(model.pendingActivityLabel, systemImage: "clock.badge.exclamationmark")
                        .accessibilityIdentifier(AccessibilityIDs.syncStatusPendingCount)

                    Label(
                        model.failureCountLabel,
                        systemImage: model.failureCount == 0 ? "checkmark.circle" : "exclamationmark.triangle.fill"
                    )
                    .foregroundColor(model.failureCount == 0 ? .secondary : .red)
                    .accessibilityIdentifier(AccessibilityIDs.syncStatusFailedCount)
                }

                Section("Actions") {
                    NavigationLink {
                        AuditTrailView(model: model, embedsNavigationStack: false)
                    } label: {
                        Label("Logs", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier(AccessibilityIDs.auditTrailOpenButton)

                    Button {
                        isMobileStatusSheetPresented = false
                        Task {
                            await model.syncNow()
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.canSyncNow)
                    .accessibilityIdentifier(AccessibilityIDs.syncNowButton)
                }
            }
            .accessibilityIdentifier(AccessibilityIDs.syncStatusOverflowSheet)
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isMobileStatusSheetPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    #endif
}

private struct BookingAppointmentSlugField: View {
    var slug: String
    var save: (String) -> String?

    @State private var draft: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(slug: String, save: @escaping (String) -> String?) {
        self.slug = slug
        self.save = save
        _draft = State(initialValue: slug)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(BookingCopy.Field.linkName, text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commitDraft)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            draft = slug
        }
        .onChange(of: slug) { newSlug in
            guard !isFocused else { return }
            draft = newSlug
            errorMessage = nil
        }
        .onChange(of: draft) { _ in
            guard isFocused else { return }
            errorMessage = nil
        }
        .onChange(of: isFocused) { focused in
            guard !focused else { return }
            commitDraft()
        }
    }

    private func commitDraft() {
        let sanitized = Self.sanitizedSlug(draft)
        guard sanitized != slug else {
            draft = slug
            errorMessage = nil
            return
        }

        if let error = save(sanitized) {
            errorMessage = error
        } else {
            draft = sanitized
            errorMessage = nil
        }
    }

    private static func sanitizedSlug(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

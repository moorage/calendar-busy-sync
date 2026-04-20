import SwiftUI

struct AppStoreScreenshotView: View {
    let mode: AppStoreScreenshotMode

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .overview:
                    overviewView
                case .mirrors:
                    mirrorsView
                case .logs:
                    logsView
                }
            }
            .navigationTitle(mode.navigationTitle)
        }
        .frame(minWidth: 1180, idealWidth: 1180, maxWidth: .infinity, minHeight: 760, idealHeight: 760, maxHeight: .infinity)
        .background(windowBackgroundColor)
    }

    private var overviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    settingsSection {
                        sectionHeader(
                            title: "Google Accounts",
                            icon: { providerBadge(assetName: "GoogleBadge") }
                        ) {
                            borderedLabel("Add Google Account", systemImage: "plus")
                        }

                        sectionDivider
                        sampleGoogleRow(
                            name: "Sous Chef Studio",
                            email: "matt@souschefstudio.com",
                            calendar: "matt@souschefstudio.com",
                            note: "Connected less than a minute ago"
                        )

                        sectionDivider
                        sampleGoogleRow(
                            name: "Client Projects",
                            email: "calendar.ops@example.com",
                            calendar: "Operations",
                            note: "Refreshed 5 minutes ago"
                        )
                    }

                    settingsSection {
                        sectionHeader(
                            title: "Apple / iCloud Calendar",
                            icon: { providerBadge(assetName: "ICloudBadge") }
                        )

                        sectionRow {
                            HStack(spacing: 12) {
                                Label("Calendar", systemImage: "calendar")
                                    .foregroundStyle(.secondary)
                                textPill("Personal")
                                Spacer()
                                borderedLabel("Refresh", systemImage: "arrow.clockwise")
                            }
                            .font(.caption)
                        }

                        sectionDivider
                        infoMessageRow("Restored Apple calendar access for this device.", timestamp: "Yesterday")
                    }

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
                            compactSetting("Share settings through iCloud", value: "On", icon: "icloud")
                        }

                        sectionDivider
                        sectionRow {
                            compactSetting("Use your own Google OAuth app", value: "Off", icon: "lock.open.display")
                        }

                        sectionDivider
                        sectionRow {
                            compactSetting("Polling", value: "Every 2 minutes", icon: "timer")
                        }

                        sectionDivider
                        sectionRow {
                            compactSetting("Log Retention", value: "Unlimited", icon: "clock.arrow.circlepath")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }

            statusLine(
                summary: "Syncing completed across 3 calendars.",
                timestamp: "5 minutes ago",
                pending: "Nothing pending",
                failures: "0 failures"
            )
        }
    }

    private var mirrorsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    settingsSection {
                        sectionHeader(
                            title: "Google Accounts",
                            icon: { providerBadge(assetName: "GoogleBadge") }
                        )

                        sectionDivider
                        sampleGoogleRow(
                            name: "Sous Chef Studio",
                            email: "matt@souschefstudio.com",
                            calendar: "matt@souschefstudio.com",
                            note: "Connected less than a minute ago"
                        )

                        sectionDivider
                        sampleGoogleRow(
                            name: "Client Projects",
                            email: "calendar.ops@example.com",
                            calendar: "Operations",
                            note: "Shared setup applied on this device"
                        )
                    }

                    settingsSection {
                        sectionHeader(
                            title: "Mirror Preview",
                            icon: {
                                Image(systemName: "rectangle.3.group.bubble.left")
                                    .foregroundStyle(.secondary)
                            }
                        )

                        ForEach(sampleMirrorRows.indices, id: \.self) { index in
                            if index > 0 {
                                sectionDivider
                            }

                            sectionRow {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text(sampleMirrorRows[index].source)
                                    Spacer()
                                    Text(sampleMirrorRows[index].target)
                                        .foregroundStyle(.secondary)
                                    Text("Busy")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }

            statusLine(
                summary: "Syncing completed across 3 calendars.",
                timestamp: "less than a minute ago",
                pending: "Nothing pending",
                failures: "0 failures"
            )
        }
    }

    private var logsView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(sampleAuditEntries.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: sampleAuditEntries[index].icon)
                                .foregroundStyle(sampleAuditEntries[index].tint)
                            Text(sampleAuditEntries[index].title)
                                .font(.headline)
                            Spacer()
                            Text(sampleAuditEntries[index].timestamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(sampleAuditEntries[index].detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                statusLine(
                    summary: "Syncing completed across 3 calendars.",
                    timestamp: "2 minutes ago",
                    pending: "Nothing pending",
                    failures: "0 failures"
                )
            }
        }
    }

    private func sampleGoogleRow(
        name: String,
        email: String,
        calendar: String,
        note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            adaptiveTrailingRow(label: {
                HStack(spacing: 8) {
                    Text(name)
                        .fontWeight(.medium)
                    Text(email)
                        .foregroundStyle(.secondary)
                }
            }, trailing: {
                borderedLabel("Remove", systemImage: "trash")
            })
            .font(.caption)

            adaptiveTrailingRow(label: {
                HStack(spacing: 8) {
                    Label("Calendar", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                    textPill(calendar)
                }
            }, trailing: {
                borderedLabel("Refresh", systemImage: "arrow.clockwise")
            })
            .font(.caption)

            infoMessageRow("Ready to mirror accepted busy commitments from this calendar.", timestamp: note)
        }
    }

    private func compactSetting(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func statusLine(summary: String, timestamp: String, pending: String, failures: String) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Text(summary)
                    .fontWeight(.medium)
                Text(timestamp)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Spacer(minLength: 8)

            Label(pending, systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(failures, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            borderedLabel("Logs", systemImage: "clock.arrow.circlepath")
            prominentLabel("Sync Now", systemImage: "arrow.clockwise")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func prominentLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func borderedLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(sectionStrokeColor, lineWidth: 1)
            )
    }

    private func textPill(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.85))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(sectionStrokeColor, lineWidth: 1)
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
        HStack(spacing: 12) {
            label()
            Spacer(minLength: 10)
            trailing()
        }
    }

    private func infoMessageRow(_ message: String, timestamp: String) -> some View {
        sectionRow {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(timestamp)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.leading, 22)
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

    private var windowBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    private var sampleMirrorRows: [(source: String, target: String)] {
        [
            ("Sous Chef Studio -> Operations", "Busy"),
            ("Personal -> matt@souschefstudio.com", "Busy"),
            ("Operations -> Personal", "Busy"),
            ("Personal -> Operations", "Busy"),
            ("matt@souschefstudio.com -> Personal", "Busy"),
            ("Operations -> matt@souschefstudio.com", "Busy")
        ]
    }

    private var sampleAuditEntries: [(title: String, detail: String, timestamp: String, icon: String, tint: Color)] {
        [
            (
                "Created busy mirror on Operations",
                "Accepted commitment from matt@souschefstudio.com now blocks 2:30 PM to 3:30 PM on Operations.",
                "less than a minute ago",
                "checkmark.circle.fill",
                .green
            ),
            (
                "Updated mirror after source move",
                "Personal calendar change shifted the mirrored busy hold to 11:00 AM.",
                "5 minutes ago",
                "arrow.triangle.2.circlepath.circle.fill",
                .blue
            ),
            (
                "Skipped duplicate busy slot",
                "A matching busy event already existed on Personal, so no extra hold was written.",
                "12 minutes ago",
                "equal.circle.fill",
                .orange
            ),
            (
                "Removed stale mirror",
                "The source event was declined, so the mirrored hold was removed from Operations.",
                "Yesterday",
                "trash.circle.fill",
                .red
            )
        ]
    }
}

extension AppStoreScreenshotMode {
    var navigationTitle: String {
        switch self {
        case .overview, .mirrors:
            return "Calendar Busy Sync"
        case .logs:
            return "Audit Trail"
        }
    }

    var windowTitle: String {
        navigationTitle
    }
}

import SwiftUI

struct AuditTrailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.auditTrailEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No Audit Events")
                            .font(.headline)
                        Text("Audit history appears here after the app records sync and account activity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List(model.auditTrailEntries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: statusIcon(for: entry.status))
                                .foregroundStyle(statusColor(for: entry.status))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(entry.timestampLabel)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier(AccessibilityIDs.auditTrailList)
                }
            }
            .navigationTitle("Audit Trail")
        }
    }

    private func statusIcon(for status: String) -> String {
        switch status.lowercased() {
        case "ready", "connected", "selected", "created", "configured", "passed":
            return "checkmark.circle.fill"
        case "working", "running", "pending":
            return "clock.fill"
        case "blocked", "failed":
            return "exclamationmark.triangle.fill"
        case "signed-out":
            return "person.crop.circle.badge.xmark"
        default:
            return "circle.fill"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "ready", "connected", "selected", "created", "configured", "passed":
            return .green
        case "working", "running", "pending":
            return .orange
        case "blocked", "failed":
            return .red
        default:
            return .secondary
        }
    }
}

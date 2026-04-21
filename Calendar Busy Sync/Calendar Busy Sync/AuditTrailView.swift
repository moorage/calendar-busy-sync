import SwiftUI

struct AuditTrailView: View {
    @ObservedObject var model: AppModel
    var embedsNavigationStack: Bool = true

    var body: some View {
        Group {
            if embedsNavigationStack {
                NavigationStack {
                    auditTrailContent
                }
            } else {
                auditTrailContent
            }
        }
    }

    private var auditTrailContent: some View {
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(entry.status.lowercased() == "failed" ? .red : .primary)
                            Spacer()
                            Text(entry.timestampLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier(AccessibilityIDs.auditTrailList)
            }
        }
        .navigationTitle("Audit Trail")
        .accessibilityIdentifier(AccessibilityIDs.auditTrailScreen)
    }
}

import Foundation

struct AuditTrailEntry: Identifiable, Equatable {
    let occurredAt: Date
    let title: String
    let detail: String
    let status: String

    var id: String {
        "\(occurredAt.timeIntervalSinceReferenceDate)|\(title)|\(detail)|\(status)"
    }

    var timestampLabel: String {
        Self.timestampFormatter.string(from: occurredAt)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

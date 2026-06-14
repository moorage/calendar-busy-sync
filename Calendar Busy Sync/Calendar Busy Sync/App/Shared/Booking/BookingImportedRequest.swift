import Foundation

nonisolated struct BookingRequestPlaintext: Codable, Equatable, Sendable {
    var requestID: BookingRequestID
    var appointmentTypeID: AppointmentTypeID
    var slotID: BookingSlotID
    var slotToken: SignedBookingSlotToken
    var visitor: BookingRequestVisitor
    var browserTimeZone: String
    var createdAt: Date
}

nonisolated struct BookingRequestVisitor: Codable, Equatable, Sendable {
    var name: String
    var email: String
    var topic: String
    var guestEmails: [String]

    init(
        name: String,
        email: String,
        topic: String,
        guestEmails: [String] = []
    ) {
        self.name = name
        self.email = email
        self.topic = topic
        self.guestEmails = guestEmails
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        topic = try container.decode(String.self, forKey: .topic)
        guestEmails = try container.decodeIfPresent([String].self, forKey: .guestEmails) ?? []
    }
}

enum BookingImportedRequestStatus: String, Equatable, Sendable {
    case pendingReview
    case approved
    case declined
    case expired
    case unavailable
    case failed

    var label: String {
        switch self {
        case .pendingReview:
            return "Ready to review"
        case .approved:
            return "Approved"
        case .declined:
            return "Declined"
        case .expired:
            return "Expired"
        case .unavailable:
            return "Time no longer open"
        case .failed:
            return "Needs attention"
        }
    }
}

struct BookingImportedRequest: Identifiable, Equatable, Sendable {
    var id: BookingRequestID
    var envelope: EncryptedBookingRequestEnvelope
    var plaintext: BookingRequestPlaintext
    var slotClaim: BookingSlotClaim
    var importedAt: Date
    var status: BookingImportedRequestStatus
    var message: String
    var calendarEventID: String?

    var visitorDisplayName: String {
        let trimmedName = plaintext.visitor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? plaintext.visitor.email : trimmedName
    }

    var topicPreview: String {
        let trimmedTopic = plaintext.visitor.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTopic.isEmpty ? "No topic provided." : trimmedTopic
    }

    var inviteeEmails: [String] {
        BookingInviteeEmailList.normalized(
            bookerEmail: plaintext.visitor.email,
            guestEmails: plaintext.visitor.guestEmails
        )
    }

    var canApprove: Bool {
        status == .pendingReview
    }

    var canDecline: Bool {
        status == .pendingReview || status == .unavailable || status == .expired || status == .failed
    }
}

enum BookingInviteeEmailList {
    static func normalized(bookerEmail: String, guestEmails: [String]) -> [String] {
        var seen: Set<String> = []
        return ([bookerEmail] + guestEmails).compactMap { rawEmail in
            let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.contains("@") else {
                return nil
            }

            let key = email.lowercased()
            guard seen.insert(key).inserted else {
                return nil
            }

            return email
        }
    }
}

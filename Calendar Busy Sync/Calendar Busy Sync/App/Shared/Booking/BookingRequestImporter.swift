import Foundation

enum BookingRequestImportError: Error, Equatable {
    case mismatchedSignedSlot
}

enum BookingRequestImporter {
    static func importEnvelope(
        _ envelope: EncryptedBookingRequestEnvelope,
        secrets: BookingLocalSecrets,
        now: Date,
        isSlotStillOpen: (BookingSlotClaim) throws -> Bool
    ) throws -> BookingImportedRequest {
        let plaintextData = try BookingRequestDecryptor.decrypt(
            envelope,
            using: try secrets.privateKey
        )
        let plaintext = try decoder.decode(
            BookingRequestPlaintext.self,
            from: plaintextData
        )
        let claim = try secrets.slotSigner.verifiedClaim(from: plaintext.slotToken)
        let status: BookingImportedRequestStatus
        let message: String

        if envelope.expiresAt <= now || claim.expiresAt <= now {
            status = .expired
            message = BookingCopy.Validation.requestExpired
        } else if plaintext.requestID != envelope.requestID
            || plaintext.appointmentTypeID != claim.appointmentTypeID
            || plaintext.slotID != claim.slotID
        {
            status = .failed
            message = "Request details do not match the signed slot."
        } else if try isSlotStillOpen(claim) {
            status = .pendingReview
            message = BookingCopy.Validation.slotStillOpen
        } else {
            status = .unavailable
            message = BookingCopy.Validation.slotNoLongerOpen
        }

        return BookingImportedRequest(
            id: envelope.requestID,
            envelope: envelope,
            plaintext: plaintext,
            slotClaim: claim,
            importedAt: now,
            status: status,
            message: message,
            calendarEventID: nil
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

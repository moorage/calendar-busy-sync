import EventKit
import Foundation

enum AppleMirrorEligibility {
    static func shouldMirror(
        blocksTime: Bool,
        organizerIsCurrentUser: Bool,
        hasAttendees: Bool,
        currentUserParticipantStatus: EKParticipantStatus?
    ) -> Bool {
        guard blocksTime else {
            return false
        }

        if organizerIsCurrentUser {
            return true
        }

        guard hasAttendees else {
            return true
        }

        return currentUserParticipantStatus == .accepted
    }
}

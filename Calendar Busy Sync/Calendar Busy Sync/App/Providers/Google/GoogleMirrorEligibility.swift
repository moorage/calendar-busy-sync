import Foundation

struct GoogleMirrorAttendee: Equatable {
    let isCurrentUser: Bool
    let responseStatus: String?
}

enum GoogleMirrorEligibility {
    static func shouldMirror(
        blocksTime: Bool,
        organizerIsCurrentUser: Bool,
        attendees: [GoogleMirrorAttendee]?
    ) -> Bool {
        guard blocksTime else {
            return false
        }

        if organizerIsCurrentUser {
            return true
        }

        guard let attendees, !attendees.isEmpty else {
            return true
        }

        guard let currentUserAttendee = attendees.first(where: \.isCurrentUser) else {
            return false
        }

        return currentUserAttendee.responseStatus?.lowercased() == "accepted"
    }
}

import Foundation

nonisolated struct BookingIcon: Equatable, Sendable {
    let primarySystemName: String
    let fallbackSystemName: String
}

nonisolated enum BookingIconography {
    static let settings = BookingIcon(primarySystemName: "calendar.badge.plus", fallbackSystemName: "calendar")
    static let incompleteSetup = BookingIcon(primarySystemName: "arrow.clockwise", fallbackSystemName: "clock")
    static let ready = BookingIcon(primarySystemName: "checkmark.circle", fallbackSystemName: "checkmark")
    static let bookingPage = BookingIcon(primarySystemName: "globe", fallbackSystemName: "link")
    static let inbox = BookingIcon(primarySystemName: "tray", fallbackSystemName: "lock")
    static let requests = BookingIcon(primarySystemName: "tray.full", fallbackSystemName: "tray")
    static let copyBookingLink = BookingIcon(primarySystemName: "link", fallbackSystemName: "doc.on.doc")
    static let openBookingPage = BookingIcon(primarySystemName: "arrow.up.right.square", fallbackSystemName: "globe")
    static let publishPage = BookingIcon(primarySystemName: "square.and.arrow.up", fallbackSystemName: "arrow.up.doc")
    static let checkInbox = BookingIcon(primarySystemName: "arrow.clockwise", fallbackSystemName: "tray")
    static let rotateInbox = BookingIcon(primarySystemName: "arrow.triangle.2.circlepath", fallbackSystemName: "arrow.clockwise")
    static let advanced = BookingIcon(primarySystemName: "gearshape", fallbackSystemName: "slider.horizontal.3")
    static let pageStep = BookingIcon(primarySystemName: "doc.text", fallbackSystemName: "doc")
    static let publishStep = BookingIcon(primarySystemName: "globe", fallbackSystemName: "link")
    static let inboxStep = BookingIcon(primarySystemName: "tray", fallbackSystemName: "lock")
    static let testStep = BookingIcon(primarySystemName: "paperplane", fallbackSystemName: "paperplane")
    static let success = BookingIcon(primarySystemName: "checkmark.circle", fallbackSystemName: "checkmark")
    static let warning = BookingIcon(primarySystemName: "exclamationmark.triangle", fallbackSystemName: "exclamationmark.triangle")
    static let expired = BookingIcon(primarySystemName: "clock", fallbackSystemName: "clock")
}

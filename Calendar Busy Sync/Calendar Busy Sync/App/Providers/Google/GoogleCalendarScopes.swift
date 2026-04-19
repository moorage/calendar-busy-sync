import Foundation

enum GoogleCalendarScopes {
    static let calendarListReadonly = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    static let calendarEvents = "https://www.googleapis.com/auth/calendar.events"

    static let required = [
        calendarListReadonly,
        calendarEvents,
    ]
}

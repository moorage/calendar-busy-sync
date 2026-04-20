import Foundation

#if os(macOS)
import AppKit
#endif

protocol AppleCalendarSettingsOpening {
    func openCalendarAccessSettings() -> Bool
}

struct AppleCalendarSettingsOpener: AppleCalendarSettingsOpening {
    static let calendarAccessSettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"

    func openCalendarAccessSettings() -> Bool {
        guard let url = URL(string: Self.calendarAccessSettingsURLString) else {
            return false
        }

        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }
}

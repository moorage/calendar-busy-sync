import Foundation

struct BookingMarkdownDocument: Equatable, Sendable {
    var frontMatter: [String: String]
    var body: String

    static func parse(_ source: String) throws -> BookingMarkdownDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard lines.first == "---" else {
            throw BookingConfigurationError.missingFrontMatter
        }

        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            throw BookingConfigurationError.invalidFrontMatter("Close front matter with --- before publishing.")
        }

        var frontMatter: [String: String] = [:]
        for line in lines[1..<closingIndex] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            guard let separatorIndex = trimmed.firstIndex(of: ":") else {
                throw BookingConfigurationError.invalidFrontMatter("Use key: value front matter before publishing.")
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
            frontMatter[key] = Self.unquoted(rawValue)
        }

        try BookingConfigurationValidator.validatePublicFrontMatter(frontMatter)

        let body = lines[(closingIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return BookingMarkdownDocument(frontMatter: frontMatter, body: body)
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}

enum BookingAppointmentMarkdownParser {
    static func parse(_ source: String) throws -> BookingAppointmentType {
        let document = try BookingMarkdownDocument.parse(source)
        let frontMatter = document.frontMatter

        let slug = try required("slug", in: frontMatter)
        try BookingIdentifierValidator.validateSlug(slug, fieldName: BookingCopy.Field.linkName)

        let idValue = frontMatter["id"] ?? slug
        let name = try required("name", in: frontMatter)
        let durationMinutes = try positiveInteger("duration_minutes", in: frontMatter)
        let availabilityHorizonDays = try boundedPositiveInteger(
            "availability_horizon_days",
            in: frontMatter,
            defaultValue: BookingAppointmentType.defaultAvailabilityHorizonDays,
            maximumValue: BookingAppointmentType.maximumAvailabilityHorizonDays
        )
        let minimumNoticeMinutes = try nonNegativeInteger("minimum_notice_minutes", in: frontMatter, defaultValue: 1440)
        let bufferBeforeMinutes = try nonNegativeInteger("buffer_before_minutes", in: frontMatter, defaultValue: 0)
        let bufferAfterMinutes = try nonNegativeInteger("buffer_after_minutes", in: frontMatter, defaultValue: 0)
        let weeklyHours = try BookingWeeklyHoursCodec.parse(frontMatter["weekly_hours"])
        let location = try parseLocation(frontMatter)
        let isAutoConfirmEnabled = bool("auto_confirm", in: frontMatter, defaultValue: false)
        let isPaused = bool("paused", in: frontMatter, defaultValue: false)
        let questions = try parseQuestions(frontMatter["questions"])

        return BookingAppointmentType(
            id: AppointmentTypeID(idValue),
            slug: slug,
            name: name,
            summary: document.body,
            durationMinutes: durationMinutes,
            availabilityHorizonDays: availabilityHorizonDays,
            minimumNoticeMinutes: minimumNoticeMinutes,
            bufferBeforeMinutes: bufferBeforeMinutes,
            bufferAfterMinutes: bufferAfterMinutes,
            weeklyHours: weeklyHours,
            location: location,
            isAutoConfirmEnabled: isAutoConfirmEnabled,
            isPaused: isPaused,
            questions: questions
        )
    }

    private static func required(_ key: String, in frontMatter: [String: String]) throws -> String {
        guard let value = frontMatter[key], !value.isEmpty else {
            throw BookingConfigurationError.missingRequiredField(key)
        }

        return value
    }

    private static func positiveInteger(_ key: String, in frontMatter: [String: String]) throws -> Int {
        guard let rawValue = frontMatter[key] else {
            throw BookingConfigurationError.missingRequiredField(BookingCopy.Field.duration)
        }

        guard let value = Int(rawValue), value > 0 else {
            throw BookingConfigurationError.invalidField("Add a duration before publishing.")
        }

        return value
    }

    private static func boundedPositiveInteger(
        _ key: String,
        in frontMatter: [String: String],
        defaultValue: Int,
        maximumValue: Int
    ) throws -> Int {
        guard let rawValue = frontMatter[key], !rawValue.isEmpty else {
            return defaultValue
        }

        guard let value = Int(rawValue), (1...maximumValue).contains(value) else {
            throw BookingConfigurationError.invalidField("Availability can be shown for at most 3 months.")
        }

        return value
    }

    private static func nonNegativeInteger(
        _ key: String,
        in frontMatter: [String: String],
        defaultValue: Int
    ) throws -> Int {
        guard let rawValue = frontMatter[key], !rawValue.isEmpty else {
            return defaultValue
        }

        guard let value = Int(rawValue), value >= 0 else {
            throw BookingConfigurationError.invalidField("\(key) must be zero or greater.")
        }

        return value
    }

    private static func bool(_ key: String, in frontMatter: [String: String], defaultValue: Bool) -> Bool {
        guard let rawValue = frontMatter[key]?.lowercased() else {
            return defaultValue
        }

        return rawValue == "true" || rawValue == "yes"
    }

    private static func parseLocation(_ frontMatter: [String: String]) throws -> BookingAppointmentLocation {
        let rawMode = (frontMatter["location"] ?? frontMatter["location_mode"] ?? "none")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let details = frontMatter["location_details"] ?? ""

        switch rawMode {
        case "", "none":
            return .none
        case "custom", "text":
            return BookingAppointmentLocation(mode: .custom, details: details)
        case "phone", "phone_call":
            return BookingAppointmentLocation(mode: .phone, details: details)
        case "google_meet", "meet", "googlemeet":
            return .googleMeet
        default:
            throw BookingConfigurationError.invalidField("Location must be none, custom, phone, or google_meet.")
        }
    }

    private static func parseQuestions(_ rawValue: String?) throws -> [BookingQuestion] {
        guard let rawValue, !rawValue.isEmpty else {
            return [
                BookingQuestion(id: "name", label: BookingCopy.PublicSite.visitorName, type: .text, isRequired: true),
                BookingQuestion(id: "email", label: BookingCopy.PublicSite.visitorEmail, type: .email, isRequired: true),
                BookingQuestion(id: "topic", label: BookingCopy.PublicSite.topicQuestion, type: .longText, isRequired: false),
            ]
        }

        return try rawValue.split(separator: ",").map { entry in
            let components = entry.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard components.count == 2 else {
                throw BookingConfigurationError.invalidField("Use question_id=question_type for appointment questions.")
            }
            guard let type = BookingQuestionType(rawValue: components[1]) else {
                throw BookingConfigurationError.unsupportedQuestionType(components[1])
            }

            return BookingQuestion(
                id: components[0],
                label: components[0].replacingOccurrences(of: "-", with: " ").capitalized,
                type: type,
                isRequired: true
            )
        }
    }
}

enum BookingWeeklyHoursCodec {
    static func parse(_ rawValue: String?) throws -> [BookingWeeklyHours] {
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return BookingWeeklyHours.weekdayDefault
        }

        let days = try rawValue.split(separator: ";").map { entry in
            let components = entry.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard components.count == 2 else {
                throw BookingConfigurationError.invalidField("Use day=HH:MM-HH:MM for weekly hours.")
            }

            let weekday = try weekdayValue(components[0])
            let windows = try workingHourWindows(components[1])
            return BookingWeeklyHours(weekday: weekday, windows: windows)
        }
        let sortedDays = days.sorted { $0.weekday < $1.weekday }
        try BookingConfigurationValidator.validateWeeklyHours(sortedDays)
        return sortedDays
    }

    static func serialize(_ weeklyHours: [BookingWeeklyHours]) -> String {
        weeklyHours
            .sorted { $0.weekday < $1.weekday }
            .map { day in
                let windows: String
                if day.windows.isEmpty {
                    windows = "closed"
                } else {
                    windows = day.windows.map { window in
                        "\(timeString(window.startMinuteOfDay))-\(timeString(window.endMinuteOfDay))"
                    }.joined(separator: "|")
                }
                return "\(weekdayName(day.weekday))=\(windows)"
            }
            .joined(separator: ";")
    }

    private static func weekdayValue(_ value: String) throws -> Int {
        switch value.lowercased() {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tues", "tuesday": return 3
        case "wed", "wednesday": return 4
        case "thu", "thur", "thurs", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default:
            throw BookingConfigurationError.invalidField("Weekly hours must use day names like mon or friday.")
        }
    }

    private static func workingHourWindows(_ value: String) throws -> [BookingWorkingHours] {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "closed" || normalized == "unavailable" || normalized == "none" {
            return []
        }

        return try value.split(separator: "|").map { range in
            let components = range.split(separator: "-", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard components.count == 2 else {
                throw BookingConfigurationError.invalidField("Use HH:MM-HH:MM ranges for weekly hours.")
            }

            let start = try minuteOfDay(components[0])
            let end = try minuteOfDay(components[1])
            guard start < end else {
                throw BookingConfigurationError.invalidField("Weekly hours must end after they start.")
            }

            return BookingWorkingHours(startMinuteOfDay: start, endMinuteOfDay: end)
        }
    }

    private static func minuteOfDay(_ value: String) throws -> Int {
        let components = value.split(separator: ":", maxSplits: 1)
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              (0...24).contains(hour),
              (0...59).contains(minute),
              !(hour == 24 && minute != 0)
        else {
            throw BookingConfigurationError.invalidField("Weekly hours must use 24-hour HH:MM times.")
        }

        return hour * 60 + minute
    }

    private static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "sun"
        case 2: return "mon"
        case 3: return "tue"
        case 4: return "wed"
        case 5: return "thu"
        case 6: return "fri"
        case 7: return "sat"
        default: return "day"
        }
    }

    private static func timeString(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

enum BookingProfileMarkdownParser {
    static func parse(_ source: String) throws -> BookingProfile {
        let document = try BookingMarkdownDocument.parse(source)
        let frontMatter = document.frontMatter
        let publicName = try required("public_name", in: frontMatter)

        return BookingProfile(
            id: BookingProfileID(frontMatter["id"] ?? "default"),
            publicName: publicName,
            pageTitle: frontMatter["page_title"] ?? BookingCopy.PublicSite.pageTitleTemplate.replacingOccurrences(
                of: "{publicName}",
                with: publicName
            ),
            pageSubtitle: document.body.isEmpty ? BookingCopy.PublicSite.pageSubtitle : document.body,
            timeZoneIdentifier: frontMatter["time_zone"] ?? TimeZone.current.identifier
        )
    }

    private static func required(_ key: String, in frontMatter: [String: String]) throws -> String {
        guard let value = frontMatter[key], !value.isEmpty else {
            throw BookingConfigurationError.missingRequiredField(key)
        }

        return value
    }
}

import CryptoKit
import Foundation

struct BookingProfile: Codable, Equatable, Sendable {
    var id: BookingProfileID
    var publicName: String
    var pageTitle: String
    var pageSubtitle: String
    var timeZoneIdentifier: String

    static let example = BookingProfile(
        id: BookingProfileID("default"),
        publicName: "Sam Rivera",
        pageTitle: "Request time with Sam",
        pageSubtitle: BookingCopy.PublicSite.pageSubtitle,
        timeZoneIdentifier: "America/Los_Angeles"
    )
}

struct BookingAppointmentType: Codable, Equatable, Identifiable, Sendable {
    static let defaultAvailabilityHorizonDays = 14
    static let maximumAvailabilityHorizonDays = 90

    var id: AppointmentTypeID
    var slug: String
    var name: String
    var summary: String
    var durationMinutes: Int
    var availabilityHorizonDays: Int
    var minimumNoticeMinutes: Int
    var bufferBeforeMinutes: Int
    var bufferAfterMinutes: Int
    var weeklyHours: [BookingWeeklyHours]
    var location: BookingAppointmentLocation
    var calendarTarget: BookingAppointmentCalendarTarget?
    var isAutoConfirmEnabled: Bool
    var isPaused: Bool
    var questions: [BookingQuestion]

    init(
        id: AppointmentTypeID,
        slug: String,
        name: String,
        summary: String,
        durationMinutes: Int,
        availabilityHorizonDays: Int = Self.defaultAvailabilityHorizonDays,
        minimumNoticeMinutes: Int,
        bufferBeforeMinutes: Int,
        bufferAfterMinutes: Int,
        weeklyHours: [BookingWeeklyHours],
        location: BookingAppointmentLocation = .none,
        calendarTarget: BookingAppointmentCalendarTarget? = nil,
        isAutoConfirmEnabled: Bool,
        isPaused: Bool = false,
        questions: [BookingQuestion]
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.summary = summary
        self.durationMinutes = durationMinutes
        self.availabilityHorizonDays = availabilityHorizonDays
        self.minimumNoticeMinutes = minimumNoticeMinutes
        self.bufferBeforeMinutes = bufferBeforeMinutes
        self.bufferAfterMinutes = bufferAfterMinutes
        self.weeklyHours = weeklyHours
        self.location = location
        self.calendarTarget = calendarTarget
        self.isAutoConfirmEnabled = isAutoConfirmEnabled
        self.isPaused = isPaused
        self.questions = questions
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case summary
        case durationMinutes
        case availabilityHorizonDays
        case minimumNoticeMinutes
        case bufferBeforeMinutes
        case bufferAfterMinutes
        case weeklyHours
        case location
        case calendarTarget
        case isAutoConfirmEnabled
        case isPaused
        case questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AppointmentTypeID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        availabilityHorizonDays = try container.decodeIfPresent(Int.self, forKey: .availabilityHorizonDays)
            ?? Self.defaultAvailabilityHorizonDays
        minimumNoticeMinutes = try container.decode(Int.self, forKey: .minimumNoticeMinutes)
        bufferBeforeMinutes = try container.decode(Int.self, forKey: .bufferBeforeMinutes)
        bufferAfterMinutes = try container.decode(Int.self, forKey: .bufferAfterMinutes)
        weeklyHours = try container.decode([BookingWeeklyHours].self, forKey: .weeklyHours)
        location = try container.decode(BookingAppointmentLocation.self, forKey: .location)
        calendarTarget = try container.decodeIfPresent(BookingAppointmentCalendarTarget.self, forKey: .calendarTarget)
        isAutoConfirmEnabled = try container.decode(Bool.self, forKey: .isAutoConfirmEnabled)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        questions = try container.decode([BookingQuestion].self, forKey: .questions)
    }

    func workingHours(forWeekday weekday: Int) -> [BookingWorkingHours] {
        weeklyHours.first { $0.weekday == weekday }?.windows ?? []
    }
}

struct BookingAppointmentCalendarTarget: Codable, Equatable, Sendable {
    var provider: BookingAppointmentCalendarTargetProvider
    var accountID: String?
    var calendarID: String

    var optionID: String {
        switch provider {
        case .apple:
            return "apple|\(calendarID)"
        case .google:
            return "google|\(accountID ?? "")|\(calendarID)"
        }
    }

    static func apple(calendarID: String) -> Self {
        BookingAppointmentCalendarTarget(provider: .apple, accountID: nil, calendarID: calendarID)
    }

    static func google(accountID: String, calendarID: String) -> Self {
        BookingAppointmentCalendarTarget(provider: .google, accountID: accountID, calendarID: calendarID)
    }

    static func parse(optionID: String) -> Self? {
        let parts = optionID.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let provider = parts.first else {
            return nil
        }

        switch provider {
        case BookingAppointmentCalendarTargetProvider.apple.rawValue:
            guard parts.count == 2 else { return nil }
            return .apple(calendarID: parts[1])
        case BookingAppointmentCalendarTargetProvider.google.rawValue:
            guard parts.count == 3 else { return nil }
            return .google(accountID: parts[1], calendarID: parts[2])
        default:
            return nil
        }
    }
}

enum BookingAppointmentCalendarTargetProvider: String, Codable, Sendable {
    case apple
    case google
}

struct BookingAppointmentLocation: Codable, Equatable, Sendable {
    var mode: BookingAppointmentLocationMode
    var details: String

    static let none = BookingAppointmentLocation(mode: .none, details: "")
    static let googleMeet = BookingAppointmentLocation(mode: .googleMeet, details: "")
}

enum BookingAppointmentLocationMode: String, Codable, CaseIterable, Sendable {
    case none
    case custom
    case phone
    case googleMeet = "google_meet"

    var label: String {
        switch self {
        case .none:
            return "No location"
        case .custom:
            return "Custom"
        case .phone:
            return "Phone call"
        case .googleMeet:
            return "Google Meet"
        }
    }
}

struct BookingWeeklyHours: Codable, Equatable, Sendable {
    var weekday: Int
    var windows: [BookingWorkingHours]

    static let weekdayDefault: [BookingWeeklyHours] = (2...6).map { weekday in
        BookingWeeklyHours(
            weekday: weekday,
            windows: [.weekdayDefault]
        )
    }
}

struct BookingQuestion: Codable, Equatable, Sendable {
    var id: String
    var label: String
    var type: BookingQuestionType
    var isRequired: Bool
}

enum BookingQuestionType: String, Codable, CaseIterable, Sendable {
    case text
    case email
    case longText = "long_text"
}

struct BookingTheme: Codable, Equatable, Sendable {
    var accentColor: String
    var backgroundColor: String
    var textColor: String

    static let defaultValue = BookingTheme(
        accentColor: "#0F766E",
        backgroundColor: "#F7F3EA",
        textColor: "#171717"
    )
}

struct BookingSiteConfiguration: Codable, Equatable, Sendable {
    var profile: BookingProfile
    var appointmentTypes: [BookingAppointmentType]
    var theme: BookingTheme
    var inboxID: BookingInboxID
    var shareID: BookingShareID
    var inboxURL: URL?
    var publicKey: BookingPublicKey

    var publicAppointmentTypes: [BookingAppointmentType] {
        appointmentTypes.filter { !$0.isPaused }
    }
}

nonisolated enum BookingPublicationFingerprint {
    static func publicSiteFingerprint(configuration: BookingSiteConfiguration) throws -> String {
        let input = PublicFingerprintInput(configuration: configuration)
        let data = try encoder.encode(input)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

private nonisolated struct PublicFingerprintInput: Encodable {
    var profile: BookingProfile
    var appointmentTypes: [PublicFingerprintAppointmentType]
    var theme: BookingTheme
    var inboxID: String
    var shareID: String
    var inboxURL: String
    var publicKey: BookingPublicKey

    init(configuration: BookingSiteConfiguration) {
        self.profile = configuration.profile
        self.appointmentTypes = configuration.publicAppointmentTypes.map(PublicFingerprintAppointmentType.init(appointmentType:))
        self.theme = configuration.theme
        self.inboxID = configuration.inboxID.rawValue
        self.shareID = configuration.shareID.rawValue
        self.inboxURL = configuration.inboxURL?.absoluteString ?? ""
        self.publicKey = configuration.publicKey
    }
}

private nonisolated struct PublicFingerprintAppointmentType: Encodable {
    var id: AppointmentTypeID
    var slug: String
    var name: String
    var summary: String
    var durationMinutes: Int
    var availabilityHorizonDays: Int
    var minimumNoticeMinutes: Int
    var bufferBeforeMinutes: Int
    var bufferAfterMinutes: Int
    var weeklyHours: [BookingWeeklyHours]
    var location: BookingAppointmentLocation
    var isAutoConfirmEnabled: Bool
    var questions: [BookingQuestion]

    init(appointmentType: BookingAppointmentType) {
        self.id = appointmentType.id
        self.slug = appointmentType.slug
        self.name = appointmentType.name
        self.summary = appointmentType.summary
        self.durationMinutes = appointmentType.durationMinutes
        self.availabilityHorizonDays = appointmentType.availabilityHorizonDays
        self.minimumNoticeMinutes = appointmentType.minimumNoticeMinutes
        self.bufferBeforeMinutes = appointmentType.bufferBeforeMinutes
        self.bufferAfterMinutes = appointmentType.bufferAfterMinutes
        self.weeklyHours = appointmentType.weeklyHours
        self.location = appointmentType.location
        self.isAutoConfirmEnabled = appointmentType.isAutoConfirmEnabled
        self.questions = appointmentType.questions
    }
}

nonisolated struct BookingConfigurationDiagnostic: Codable, Equatable, Sendable {
    enum Severity: String, Codable, Sendable {
        case error
        case warning
    }

    var severity: Severity
    var message: String
}

enum BookingConfigurationError: LocalizedError, Equatable {
    case missingFrontMatter
    case invalidFrontMatter(String)
    case missingRequiredField(String)
    case invalidField(String)
    case duplicateSlug(String)
    case unsupportedQuestionType(String)
    case unsafePublicValue(String)
    case invalidRelayURL(String)
    case diagnostics([BookingConfigurationDiagnostic])

    var errorDescription: String? {
        switch self {
        case .missingFrontMatter:
            return "Add front matter before publishing."
        case let .invalidFrontMatter(message):
            return message
        case let .missingRequiredField(field):
            return "Add \(field) before publishing."
        case let .invalidField(message):
            return message
        case let .duplicateSlug(slug):
            return "Another appointment type already uses \(slug)."
        case let .unsupportedQuestionType(type):
            return "Question type \(type) is not supported."
        case let .unsafePublicValue(message):
            return message
        case let .invalidRelayURL(message):
            return message
        case let .diagnostics(diagnostics):
            return diagnostics.map(\.message).joined(separator: "\n")
        }
    }

    var localizedDescription: String {
        errorDescription ?? "Booking configuration failed."
    }
}

enum BookingConfigurationValidator {
    private static let secretTerms = [
        "access_token",
        "refresh_token",
        "client_secret",
        "private_key",
        "api_key",
        "secret",
        "oauth",
        "bearer "
    ]

    static func validateAppointmentTypes(_ appointmentTypes: [BookingAppointmentType]) throws {
        var slugs: Set<String> = []

        for appointmentType in appointmentTypes {
            try BookingIdentifierValidator.validateSlug(appointmentType.slug, fieldName: BookingCopy.Field.linkName)

            guard appointmentType.durationMinutes > 0 else {
                throw BookingConfigurationError.invalidField("Add a duration before publishing.")
            }

            guard (1...BookingAppointmentType.maximumAvailabilityHorizonDays).contains(appointmentType.availabilityHorizonDays) else {
                throw BookingConfigurationError.invalidField("Availability can be shown for at most 3 months.")
            }

            try validateWeeklyHours(appointmentType.weeklyHours)

            guard slugs.insert(appointmentType.slug).inserted else {
                throw BookingConfigurationError.duplicateSlug(appointmentType.slug)
            }
        }
    }

    static func validateWeeklyHours(_ weeklyHours: [BookingWeeklyHours]) throws {
        var weekdays: Set<Int> = []
        for day in weeklyHours {
            guard (1...7).contains(day.weekday) else {
                throw BookingConfigurationError.invalidField("Weekly hours must use weekdays Sunday through Saturday.")
            }
            guard weekdays.insert(day.weekday).inserted else {
                throw BookingConfigurationError.invalidField("Weekly hours can list each weekday only once.")
            }
            for window in day.windows {
                guard window.startMinuteOfDay >= 0,
                      window.endMinuteOfDay <= 24 * 60,
                      window.startMinuteOfDay < window.endMinuteOfDay
                else {
                    throw BookingConfigurationError.invalidField("Weekly hours must use valid start and end times.")
                }
            }
        }
    }

    static func validatePublicFrontMatter(_ frontMatter: [String: String]) throws {
        for (key, value) in frontMatter {
            let combinedValue = "\(key): \(value)".lowercased()
            if secretTerms.contains(where: combinedValue.contains) {
                throw BookingConfigurationError.unsafePublicValue(
                    "This field looks like a secret. Remove it before publishing."
                )
            }

            if combinedValue.contains("@gmail.com") || combinedValue.contains("@googlemail.com") {
                throw BookingConfigurationError.unsafePublicValue(
                    "Remove calendar account emails before publishing."
                )
            }
        }
    }
}

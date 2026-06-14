import Foundation

struct BookingStaticSiteArtifact: Equatable, Sendable {
    var relativePath: String
    var data: Data

    var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

enum BookingStaticSiteGenerator {
    static func artifacts(
        configuration: BookingSiteConfiguration,
        slots: [BookingOpenSlot],
        generatedAt: Date,
        expiresAt: Date
    ) throws -> [BookingStaticSiteArtifact] {
        let siteConfig = PublicSiteConfig(configuration: configuration)
        let availability = PublicAvailability(
            generatedAt: generatedAt,
            expiresAt: expiresAt,
            slots: slots.map(PublicSlot.init(slot:))
        )
        let configData = try encoder.encode(siteConfig)
        let availabilityData = try encoder.encode(availability)

        for data in [configData, availabilityData] {
            let findings = BookingPublicArtifactAuditor.findings(in: String(decoding: data, as: UTF8.self))
            guard findings.isEmpty else {
                throw BookingConfigurationError.unsafePublicValue(findings.joined(separator: " "))
            }
        }

        return [
            BookingStaticSiteArtifact(relativePath: "public/site-config.json", data: configData),
            BookingStaticSiteArtifact(relativePath: "public/availability/slots.json", data: availabilityData),
        ]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

private nonisolated struct PublicSiteConfig: Encodable {
    var version: PublicVersion
    var profile: PublicProfile
    var theme: BookingTheme
    var copy: PublicCopy
    var share: PublicShare
    var inbox: PublicInbox
    var encryption: PublicEncryption
    var appointmentTypes: [PublicAppointmentType]

    init(configuration: BookingSiteConfiguration) {
        self.version = PublicVersion(fingerprint: (try? BookingPublicationFingerprint.publicSiteFingerprint(configuration: configuration)) ?? "")
        self.profile = PublicProfile(profile: configuration.profile)
        self.theme = configuration.theme
        self.copy = PublicCopy()
        self.share = PublicShare(id: configuration.shareID.rawValue)
        self.inbox = PublicInbox(
            id: configuration.inboxID.rawValue,
            url: configuration.inboxURL?.absoluteString ?? ""
        )
        self.encryption = PublicEncryption(
            keyID: configuration.publicKey.keyID,
            publicKeyJwk: configuration.publicKey.jwk
        )
        self.appointmentTypes = configuration.publicAppointmentTypes.map(PublicAppointmentType.init(appointmentType:))
    }
}

private nonisolated struct PublicVersion: Encodable {
    var fingerprint: String
}

private nonisolated struct PublicProfile: Encodable {
    var publicName: String
    var pageTitle: String
    var pageSubtitle: String
    var timeZone: String

    init(profile: BookingProfile) {
        self.publicName = profile.publicName
        self.pageTitle = profile.pageTitle
        self.pageSubtitle = profile.pageSubtitle
        self.timeZone = profile.timeZoneIdentifier
    }
}

private nonisolated struct PublicCopy: Encodable {
    var privacyNote = BookingCopy.PublicSite.privacyNote
}

private nonisolated struct PublicShare: Encodable {
    var id: String
}

private nonisolated struct PublicInbox: Encodable {
    var id: String
    var url: String
}

private nonisolated struct PublicEncryption: Encodable {
    var keyID: String
    var publicKeyJwk: [String: String]
}

private nonisolated struct PublicAppointmentType: Encodable {
    var id: String
    var slug: String
    var name: String
    var summary: String
    var durationMinutes: Int
    var availabilityHorizonDays: Int
    var weeklyHours: [PublicWeeklyHours]
    var location: PublicAppointmentLocation
    var autoConfirm: Bool

    init(appointmentType: BookingAppointmentType) {
        self.id = appointmentType.id.rawValue
        self.slug = appointmentType.slug
        self.name = appointmentType.name
        self.summary = appointmentType.summary
        self.durationMinutes = appointmentType.durationMinutes
        self.availabilityHorizonDays = appointmentType.availabilityHorizonDays
        self.weeklyHours = appointmentType.weeklyHours.map(PublicWeeklyHours.init(day:))
        self.location = PublicAppointmentLocation(location: appointmentType.location)
        self.autoConfirm = appointmentType.isAutoConfirmEnabled
    }
}

private nonisolated struct PublicAppointmentLocation: Encodable {
    var mode: String
    var details: String

    init(location: BookingAppointmentLocation) {
        self.mode = location.mode.rawValue
        self.details = location.details
    }
}

private nonisolated struct PublicWeeklyHours: Encodable {
    var weekday: Int
    var windows: [PublicWorkingHours]

    init(day: BookingWeeklyHours) {
        self.weekday = day.weekday
        self.windows = day.windows.map(PublicWorkingHours.init(hours:))
    }
}

private nonisolated struct PublicWorkingHours: Encodable {
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int

    init(hours: BookingWorkingHours) {
        self.startMinuteOfDay = hours.startMinuteOfDay
        self.endMinuteOfDay = hours.endMinuteOfDay
    }
}

private nonisolated struct PublicAvailability: Encodable {
    var generatedAt: Date
    var expiresAt: Date
    var slots: [PublicSlot]
}

private nonisolated struct PublicSlot: Encodable {
    var id: String
    var appointmentTypeID: String
    var startsAt: Date
    var endsAt: Date
    var expiresAt: Date
    var token: String

    init(slot: BookingOpenSlot) {
        self.id = slot.id.rawValue
        self.appointmentTypeID = slot.appointmentTypeID.rawValue
        self.startsAt = slot.interval.start
        self.endsAt = slot.interval.end
        self.expiresAt = slot.interval.start
        self.token = slot.token.rawValue
    }
}

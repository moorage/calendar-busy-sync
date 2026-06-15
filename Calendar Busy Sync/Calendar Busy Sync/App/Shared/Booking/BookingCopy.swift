import Foundation

nonisolated enum BookingCopy {
    enum Settings {
        static let title = "Booking"
        static let subtitle = "Let people request time without sharing your calendars."
        static let setUpTitle = "Set up a booking page"
        static let setUpBody = "Create a public page, connect a private request inbox, and test the flow before you share a link."
        static let setUpAction = "Set up booking"
        static let finishTitle = "Finish booking setup"
        static let finishBody = "Continue from the last completed step."
        static let finishAction = "Continue setup"
        static let readyTitle = "Booking is ready"
        static let readyBody = "Your page is published and this app can receive encrypted requests."
    }

    enum StatusCard {
        static let bookingPageTitle = "Booking page"
        static let inboxTitle = "Request inbox"
        static let requestsTitle = "Requests"
        static let noBookingRequests = "No booking requests"
    }

    enum Action {
        static let generatePageFiles = "Generate page files"
        static let previewPage = "Preview page"
        static let editAppointmentTypes = "Edit appointment types"
        static let publishPage = "Publish page"
        static let generateDeployKey = "Generate deploy key"
        static let copyDeployKey = "Copy public key"
        static let verifyDeployKey = "Verify deploy key"
        static let copyRequiredPermissions = "Copy required permissions"
        static let runDryRun = "Refresh page files"
        static let deployCloudflareInbox = "Deploy Cloudflare inbox"
        static let deployVercelInbox = "Deploy Vercel inbox"
        static let copyAllowedWebsite = "Copy allowed website"
        static let pasteInboxURL = "Paste inbox URL"
        static let checkInbox = "Check inbox"
        static let sendTestRequest = "Send test request"
        static let importRequests = "Import requests"
        static let approveTestRequest = "Approve test request"
        static let copyBookingLink = "Copy booking link"
        static let openBookingPage = "Open booking page"
        static let rotateInbox = "Rotate inbox"
        static let advancedBookingSettings = "Advanced booking settings"
        static let bookingSettings = "Booking settings"
        static let viewRequestHistory = "View history"
        static let automaticBookingApproval = "Automatically accept requests"
    }

    enum SetupStep {
        static let pageHeading = "Create your booking page"
        static let pageBody = "Choose what people can request. Your calendar details stay on this device."
        static let publishHeading = "Publish with GitHub Pages"
        static let publishBody = "The app publishes only public page files and signed open slots."
        static let inboxHeading = "Connect a private request inbox"
        static let inboxBody = "The inbox stores encrypted requests until this app reads them."
        static let testHeading = "Test and share"
        static let testBody = "Send a test request before you share the link."
    }

    enum Field {
        static let publicName = "Public name"
        static let pageTitle = "Page title"
        static let appointmentName = "Appointment name"
        static let duration = "Duration"
        static let minimumNotice = "Minimum notice"
        static let bufferBefore = "Buffer before"
        static let bufferAfter = "Buffer after"
        static let appointmentType = "Appointment type"
        static let weeklyHours = "Weekly hours"
        static let location = "Location"
        static let githubRepository = "GitHub repository"
        static let bookingPageURL = "Booking page URL"
        static let allowedWebsite = "Allowed website"
        static let vercelToken = "Vercel token"
        static let vercelProject = "Vercel project ID or name"
        static let vercelTeam = "Vercel team ID or slug (optional)"
        static let linkName = "Link name"
    }

    enum Validation {
        static let deployKeyWorks = "Deploy key works for this repository."
        static let deployKeyRejected = "Deploy key does not work for this repository. Check that it has write access, then verify again."
        static let repositoryNotFound = "Repository not found. Check the owner and repository name."
        static let pagesNotEnabled = "GitHub Pages is not enabled for this repository. Open GitHub Pages settings, then validate again."
        static let dryRunReady = "Page files ready. Review them before publishing."
        static let publishSucceeded = "Booking page published."
        static let publishFailed = "Could not publish the page. Check the deploy key and try again."
        static let inboxReachable = "Inbox is reachable."
        static let inboxUnreachable = "Cannot reach the inbox. Check the URL, then try again."
        static let allowedWebsiteMismatch = "Inbox rejected the booking page. Copy the allowed website and update the inbox settings."
        static let testRequestSent = "Test request sent."
        static let testRequestFailed = "Could not send a test request. Check the page and inbox, then try again."
        static let testRequestImported = "Test request received and decrypted."
        static let testRequestMissing = "No test request found yet. Check the inbox, then import again."
        static let slotStillOpen = "This time is still open."
        static let slotNoLongerOpen = "This time is no longer open. Decline the request or suggest another time."
        static let requestExpired = "Request expired. Ask the person to choose another time."
        static let calendarWriteSucceeded = "Booking added to your calendar."
        static let calendarWriteFailed = "Could not add the booking. Check calendar access, then try again."
    }

    enum PublicSite {
        static let pageTitleTemplate = "Request time with {publicName}"
        static let pageSubtitle = "Choose a time and send a private request."
        static let privacyNote = ""
        static let chooseATime = "Choose a time"
        static let timeZoneTemplate = "Times shown in {timeZone}"
        static let visitorName = "Name"
        static let visitorEmail = "Email"
        static let topicQuestion = "What should we cover?"
        static let sendRequest = "Send request"
        static let bookThisTime = "Book this time"
        static let manualSuccessTitle = "Request sent"
        static let manualSuccessBody = "You will get a confirmation after this time is reviewed."
        static let autoConfirmSuccessTitle = "Booked"
        static let autoConfirmSuccessBody = "A calendar invite is on the way."
        static let expiredSlotMessage = "This time is no longer available. Choose another time."
        static let inboxUnavailableMessage = "Requests are not available right now. Try again later."
        static let encryptionUnavailableMessage = "This browser cannot encrypt the request. Try another browser."
    }
}

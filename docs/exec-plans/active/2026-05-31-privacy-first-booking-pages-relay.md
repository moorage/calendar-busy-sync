# Privacy-First Booking Pages and Encrypted Relay

## Purpose / Big Picture

Add a self-hosted, privacy-first appointments workflow to Calendar Busy Sync without turning the open-source app or its helper services into calendar-data custodians.

The desired user story is:

- the user runs Calendar Busy Sync locally on macOS, iPhone, or iPad
- the app can generate and publish a simple Calendly-style booking page to a GitHub Pages site owned by the user
- appointment types, page copy, theme, and layout live in Markdown files that an AI coding agent such as Codex CLI or Claude Code CLI can safely edit
- visitors can open shareable booking URLs without creating an account
- visitor requests flow through a minimal encrypted relay deployed by the user on either Cloudflare Workers or Vercel
- the relay stores and forwards only encrypted request envelopes and never receives calendar credentials, provider tokens, calendar IDs, provider event IDs, or plaintext booking details
- the native app remains the sole authority for live availability checks, approval, calendar writes, and sync/mirror side effects

This plan is intentionally product, architecture, and onboarding heavy. The hardest part is not rendering a static page. The hard part is making self-hosting understandable for non-infrastructure users while preserving the repo's privacy invariants and the open-source expectation that secrets are local, easy to rotate, and never committed.

## Progress

- [x] 2026-05-31T20:51Z create an executable plan for self-hosted GitHub Pages booking sites, Markdown customization, and user-owned encrypted relays on Cloudflare or Vercel
- [x] 2026-05-31T22:18Z consult Apple's current HIG and revise the plan around a platform-native, interactive setup assistant instead of a dense deployment form
- [x] 2026-05-31T22:28Z add a concrete copy and iconography specification for the booking setup, steady-state settings, request workflow, public booking page, and docs/video entry points
- [x] 2026-05-31T23:42Z implement the first shared booking domain slice: copy registry, icon registry, semantic IDs, Markdown parsing, config validation, signed slot tokens, availability compilation, public artifact generation, encrypted envelope decryption, and request ledger dedupe
- [x] 2026-05-31T23:42Z add a compact Booking section to the existing settings shell with fixed status copy, setup actions, and stable accessibility identifiers
- [x] 2026-05-31T23:42Z add the no-build GitHub Pages booking-site template, Markdown content examples, browser-side request encryption, and AI customization guide
- [x] 2026-05-31T23:42Z add Cloudflare Workers and Vercel encrypted request inbox templates with create/list/delete/health endpoints and documented abuse controls
- [x] 2026-05-31T23:42Z add self-hosting docs, setup video-script generation, booking fixtures, and validation scripts for the booking site plus both relay templates
- [x] 2026-06-01T06:58Z wire the native Booking settings slice to local page-file generation, persisted booking page/inbox URLs, HTTPS page verification, and request inbox health checks
- [x] 2026-06-01T06:58Z add app-side relay request building, public JWK export, static artifact writing, and draft factory coverage
- [x] 2026-06-01T06:58Z fix the public JSON wire format so booking identifiers and signed slot tokens encode as strings rather than raw-value objects
- [x] 2026-06-01T06:58Z fix availability suppression to use half-open interval overlap semantics so adjacent busy intervals do not remove valid preceding slots
- [x] 2026-06-01T07:54Z perform a live self-hosting test with `moorage/booking-test` on GitHub Pages and a Vercel relay backed by Vercel Blob
- [x] 2026-06-01T07:54Z fix live-test defects in the Vercel template: missing public route rewrites, incorrect DELETE helper import depth, and Blob access mode
- [x] 2026-06-01T07:54Z fix the static-site build script so generated demo availability matches Markdown appointment IDs and uses future slots
- [x] 2026-06-01T08:20Z wire booking draft generation to selected Apple / iCloud busy intervals, publish 40 real-calendar-derived open slots to the live Pages test site, and submit/delete a live encrypted request against one of those slots
- [x] 2026-06-01T16:20Z replace the inert `Continue setup` vertical-slice action with a working in-app setup sheet for Page, Publish, Inbox, and Test steps
- [x] 2026-06-01T16:58Z fix the setup sheet to open the next actionable step from the current snapshot, including the ready-state Test step instead of the first Page step
- [x] 2026-06-01T16:58Z replace the fake local setup test action with a browser-style encrypted test request sent through the published GitHub Pages config and the configured request inbox
- [x] 2026-06-01T16:58Z validate the macOS app manually against `https://moorage.github.io/booking-test/` and `https://live-booking-relay-vercel.vercel.app`; the setup sheet reported `2 pending` and `Test request sent.`
- [x] 2026-06-01T17:10Z validate the public GitHub Pages visitor form in Chrome via Computer Use; selecting the 30 minute meeting, entering the Matt Moore test booker details, and pressing `Send request` produced the page's reviewed-confirmation success state
- [x] 2026-06-01T17:25Z persist booking private keys and slot-signing secrets in secure storage so app-generated Pages drafts can later decrypt and verify requests for that page
- [x] 2026-06-01T17:25Z add app-side encrypted request import, local decrypt/verify/recheck state, request list UI, approve/decline actions, and inbox admin-token storage
- [x] 2026-06-01T17:25Z add Apple Calendar booking-event writes after live availability recheck, with relay delete-after-approval and focused AppModel coverage for import through approval into calendar write
- [x] 2026-06-01T18:05Z regenerate the live Pages artifacts from the signed app's current Apple / iCloud calendar access, republish `moorage/booking-test`, import live encrypted requests through the app, approve one request, write it to the selected iCloud calendar, and verify the relay record was deleted
- [x] 2026-06-01T18:34Z replace the public booking page's plain time select with a Calendly-style calendar/time picker, timezone dropdown, selected-time `Next` transition, details step, back action, and guest email fields
- [x] 2026-06-01T19:05Z preserve encrypted guest emails during request import, add Google attendee invites on booking writes, and generate an invite-populated `.ics` file for iCloud approvals because EventKit cannot programmatically set attendees
- [x] 2026-06-01T19:58Z disable public booking page month arrows when there are no bookable slots in that direction, and publish the live `moorage/booking-test` update at commit `1e85024`
- [x] 2026-06-01T20:10Z send decline notices instead of only deleting declined requests: Google creates a declined-owner calendar event with attendee updates, while iCloud writes a decline `.ics` reply artifact with invitees populated
- [x] 2026-06-01T20:38Z make the static booking page default link-preview image, favicon, and touch icon use the Calendar Busy Sync app icon, and publish the live `moorage/booking-test` update at commit `4606b68`
- [x] 2026-06-01T20:45Z add per-appointment weekly hours to Markdown, public site config, demo site generation, and app-side draft slot generation
- [x] 2026-06-01T21:12Z keep the native Booking panel short by moving page/inbox/admin-token fields into Booking settings, filtering approved/declined requests out of the active inbox, adding request history, and replacing draft and dry-run button copy with page-file language
- [x] 2026-06-01T21:34Z add appointment-type deep links: the native Booking page row can select an appointment type, open its public URL, copy it, and the static site preselects appointment cards from `?appointment=...`; publish the live `moorage/booking-test` update at commit `b262a7a`
- [x] 2026-06-01T22:02Z add a local `Automatically accept requests` Booking setting that auto-approves newly imported requests only after decrypting, validating the signed slot, rechecking live availability, writing the calendar event, and deleting the relay record
- [x] 2026-06-01T22:20Z make the Booking settings sheet show the exact calendar target used for accepted bookings, with Apple/iCloud and Google calendar pickers available in the same surface as automatic acceptance
- [x] 2026-06-01T22:35Z preserve the public booking page's time-list scroll position when a visitor selects a lower time slot, validate the behavior in Chrome, and publish the live `moorage/booking-test` update at commit `436d833`
- [x] 2026-06-01T22:48Z add removable guest email rows to the public booking details form, clear dynamic guest rows after successful submission, validate add/remove behavior in Chrome, and publish the live `moorage/booking-test` update at commit `938082a`
- [x] 2026-06-01T23:02Z make the Booking settings calendar-target area actionable from the empty state by showing Apple Calendar connect and Google account add controls before any target calendar is selected
- [x] 2026-06-01T23:16Z move the public booking details-step Back control above the `Enter details` heading, add a left-arrow label, validate placement in Chrome, and publish the live `moorage/booking-test` update at commit `07fe439`
- [x] 2026-06-01T23:28Z show a larger `Selected <date> at <time>.` summary above the public booking details form's name and email fields, validate placement/font size in Chrome, and publish the live `moorage/booking-test` update at commit `08c7299`
- [x] 2026-06-01T23:52Z revise this plan for multiple appointment-type creation, a unified Booking workspace, explicit local page-file location/open-in-Finder/publish controls, Vercel setup requirements and verification, Google Meet creation, per-type working hours, buffers, minimum notice, and HIG-informed setup ergonomics
- [x] 2026-06-02T00:06Z implement the first unified Booking workspace slice: native appointment create/duplicate/delete/edit controls, per-type hours/buffers/minimum notice/location/auto-acceptance, template-seeded page-file generation, Finder access, GitHub Pages publish settings and contents upload, Vercel relay metadata fields, secure GitHub-token storage, per-type auto-accept import policy, and Google Meet conference creation for Google Calendar approvals
- [x] 2026-06-02T22:42Z replace the raw native appointment-type form with a Calendly-style selected-card editor, disclosure sections for duration/location/availability, visual weekly-hours controls, and tests that confirm booking notes are preserved in Google and ICS calendar payloads
- [x] 2026-06-02T22:48Z remove the Booking settings sheet's oversized whitespace by replacing the nested navigation title and system segmented picker with a compact custom header and deterministic segmented selector
- [x] 2026-06-03T09:55Z audit the booking appointment-management UX/IA with source inspection, local public-page browser walkthroughs, and macOS harness capture; record the comprehensive report in `docs/ideas/backlog/booking-appointment-management-ux-ia-audit.md`
- [x] 2026-06-04T05:13Z fix the Booking workspace Page/Publish action affordances: local preview opens the generated `index.html` through AppKit on macOS, Publish-pane verification results are visible in-place, prominent button styling now follows the current page lifecycle state, and the Vercel setup field now names the optional team/account target instead of the ambiguous scope term
- [x] 2026-06-04T05:31Z replace the inline appointment-type list/editor with a list-to-detail flow, move accepted-booking target calendar selection into each appointment type, use the per-type target for approval/decline writes and Google Meet gating, and relabel booking page fingerprints as latest local/live page versions
- [x] 2026-06-04T05:39Z make template customization reachable to end users: bundle the seed `booking-site` template, seed a persistent editable `BookingSiteTemplate` folder in Application Support, generate public page files from that editable folder, and surface an `Open template folder` action in the Public Page workspace
- [x] 2026-06-05T06:21Z make GitHub Pages publishing root-only: remove the remote folder field, publish generated files at repository root, and reject repositories whose root already contains non-generated files
- [x] 2026-06-05T06:36Z plan the deploy-key-only GitHub publishing migration: remove PAT-based Contents API upload, generate/store a repository deploy key, and publish root files through Git over SSH
- [x] 2026-06-05T07:05Z implement deploy-key-only publishing: replace Contents API upload with Git-over-SSH, add deploy-key generation/verification UI and secure private-key storage, update docs/tests, and validate live read/write access on `moorage/booking-test`
- [x] 2026-06-14T07:24Z sync native Booking setup through iCloud shared configuration, including appointment types and page/inbox/publish fields, while keeping Keychain secrets and editable HTML/design template files device-local
- [x] 2026-06-14T07:31Z add a per-appointment availability horizon, cap it at three months, publish all slots for every active appointment type across its configured horizon, and reuse the poll-driven GitHub publish path so hosted availability stays current
- [x] 2026-06-15T00:00Z remove production reliance on `/usr/bin/git`, `/usr/bin/ssh`, and `/usr/bin/ssh-keygen` so App Store builds publish only through app-bundled Git/SSH helpers or a later in-process Git implementation
- [x] 2026-06-15T00:00Z replace the raw Vercel inbox URL/admin-token setup with an app-managed Vercel flow that takes a Vercel token plus project ID/name, stores generated relay secrets locally, deploys/redeploys the relay template, and records the resulting inbox URL
- [x] 2026-06-17T22:15Z make the app-managed Vercel flow provision and connect Vercel Blob storage before deploying the inbox relay
- [x] 2026-06-17T23:10Z make booking configuration failures bridge to human localized messages so GitHub deploy-key and Pages publish audit entries are actionable
- [x] 2026-06-17T23:45Z surface missing local deploy-key private keys and missing bundled Git/SSH helpers directly in Booking action messages
- [x] 2026-06-18T21:04Z bundle the macOS Git/SSH publishing helper toolchain into app builds, set `GIT_EXEC_PATH` to the bundled `booking-git-core`, and verify the built app no longer lacks the helper executables

## Surprises & Discoveries

- 2026-05-31: CloudKit is a poor default for public booking links because an iCloud-authenticated write flow adds unacceptable visitor friction, while anonymous public writes would weaken quota-abuse controls.
- 2026-05-31: the right abstraction is a blind relay, not a scheduling backend. The relay should have no endpoint that can read availability, write calendars, exchange OAuth tokens, or decide whether a request is bookable.
- 2026-05-31: GitHub Pages fits the static-site constraint, but GitHub token setup must be treated as a user-owned publishing integration with least-privilege repository access and clear rotation guidance.
- 2026-05-31: Cloudflare's Deploy to Cloudflare button and Vercel's Deploy Button both support guided self-deploy flows, but the plan must also include text and video instructions because the user may prefer CLI setup or need to audit what the app asks for.
- 2026-05-31: Apple HIG onboarding guidance favors fast, optional, interactive learning and context-specific tips over long prerequisite instruction. The booking setup needs to let people safely complete one real action per step, not read a deployment manual inside the app.
- 2026-05-31: Apple HIG sheet guidance says complex or prolonged flows should not live in stacked sheets. Booking setup should use a dedicated macOS window or settings pane and a navigation/full-screen task flow on iOS/iPadOS, with docs and deploy pages opened as secondary tasks.
- 2026-05-31: Apple HIG settings and disclosure guidance supports moving advanced knobs behind disclosure controls and keeping the main setup path focused on the handful of choices most people need.
- 2026-05-31: the user-facing concept should be "request inbox" rather than "relay" in primary UI. "Relay" is accurate technically, but "inbox" better matches the user's mental model and still preserves the architecture boundary in docs and Advanced.
- 2026-05-31: this Xcode environment repeatedly hung before Swift compilation at SwiftBuild's clang macro-discovery step, including build-only runs. A later sequential direct build and unit run completed, so future validation should avoid parallel `xcodebuild` commands that share the same DerivedData tree.
- 2026-06-01: the generated public contract needed explicit single-value Codable implementations for semantic IDs and signed slot tokens. The default RawRepresentable encoding would have produced `{"rawValue":"..."}` objects that the static site and relay contracts do not expect.
- 2026-06-01: `DateInterval.intersects` was too conservative for slot generation because adjacent intervals can be treated as intersecting. Booking availability now uses half-open overlap semantics: `a.start < b.end && b.start < a.end`.
- 2026-06-01: the app target's `-default-isolation=MainActor` requires pure booking DTO and registry types to opt out with `nonisolated` where they are used by nonisolated encoders/decoders and tests.
- 2026-06-01: Vercel Functions are served under `/api/...` unless configured otherwise. The relay template needs rewrites so the public contract remains `/healthz` and `/v1/inboxes/...`.
- 2026-06-01: Vercel Blob public/private access is a real deployment constraint, not just a docs choice. The working template uses a public Blob store and relies on the stronger invariant that every stored request record is already encrypted and contains no calendar data or visitor plaintext.
- 2026-06-01: live Pages testing showed the CLI build script could produce mismatched demo slot IDs when Markdown changed appointment slugs. The script now generates future demo availability from the parsed appointment types.
- 2026-06-01: iCloud calendar access is an EventKit/TCC permission on the signed app bundle, not a reusable keychain token. Real-calendar availability tests should run through the app bundle; Google auth remains the keychain-backed provider path.
- 2026-06-01: the signed macOS app is sandboxed, so local booking page files written by the app land under `~/Library/Containers/com.matthewpaulmoore.Calendar-Busy-Sync/Data/Library/Application Support/...`, not the unsandboxed Application Support path used by unsigned harness builds.
- 2026-06-01: the compact settings slice made `Continue setup` look production-ready even though it still called the older page-file/verify action. The plan noted a dedicated assistant as remaining work, but validation did not include clicking the primary setup action in the rendered app.
- 2026-06-01: the first setup-sheet implementation exposed another stale guard: `Generate page files` was disabled for a brand-new setup because it still depended on `hasStarted`. First-run setup actions must be validated from a clean state, not only from an already-started configuration.
- 2026-06-01: launching the unsigned macOS debug build directly can block on Google keychain session restore before the settings UI is inspectable. The app now honors the existing unsigned-build Google Sign-In environment guard before touching saved Google sessions, which keeps the booking setup UI testable while still explaining that signed builds are required for Google auth persistence.
- 2026-06-01: SwiftUI picker state can preserve an old setup step after the underlying booking snapshot becomes ready. The setup sheet now derives its initial selected step from the snapshot each time `Continue setup` opens, while still allowing explicit user step changes inside the sheet.
- 2026-06-01: the live Pages site emits browser-standard JWK values such as `"ext": true`, while the native sender originally expected every JWK value to be a string. App-side public-config decoding now accepts boolean and numeric JWK values and normalizes them before importing the public key.
- 2026-06-01: the first live Pages artifacts were generated before the native app persisted its booking private key and signing secret, so those old requests cannot be imported by the app. Regenerating and republishing the page from the current app creates a decryptable inbox/key pairing.
- 2026-06-01: WebCrypto accepts JWK `ext` as a boolean, but the Swift static generator previously emitted it as the string `"true"`. The generated app-side public JWK now omits optional `ext` so browser import stays standards-compliant.
- 2026-06-01: approval has two side effects with different durability: calendar write and relay deletion. The app now treats a successful calendar write as approval even if deleting the encrypted relay record fails, and records that cleanup failure in the audit trail rather than risking a duplicate approval retry.
- 2026-06-01: the public booking page's browser-generated ephemeral ECDH JWK also includes non-string `key_ops` and `ext` members. The app importer now decodes browser JWK dictionaries lossily, and the static page now posts only the public `kty`, `crv`, `x`, and `y` fields needed for decryption.
- 2026-06-01: date headings in a custom calendar must format the appointment-date key in UTC. Formatting a `YYYY-MM-DD` key through the viewer's local timezone can shift the displayed heading to the previous day even while the selected calendar day is correct.
- 2026-06-01: EventKit can write an iCloud event but does not expose a supported way for this app to add attendees to that event. iCloud attendee invitations therefore need a separate RFC 5545 `.ics` artifact with the booker and guest `ATTENDEE` lines populated.
- 2026-06-01: decline has the same provider split as approval. Google can create a private transparent booking-decline event with `attendees`, `responseStatus=declined` for the owner, and `sendUpdates=all`; EventKit still cannot send mail, so iCloud decline uses a local RFC 5545 `METHOD:REPLY` artifact with the owner attendee marked `PARTSTAT=DECLINED`.
- 2026-06-01: a booking inbox grows quickly once approved and declined requests remain visible. The steady-state Booking panel should show active work only, with full history one click away and setup credentials in a settings surface.
- 2026-06-01: appointment-type links need to be specific enough to share. A generic booking page URL is useful for browsing all types, but the steady-state UI should generate `?appointment=<slug>` deep links from the selected appointment type.
- 2026-06-01: automatic acceptance must stay native-app-local. The public page and relay still cannot decide bookability; the app may only auto-accept after the same import/decrypt/slot-token/live-calendar/calendar-write path used by manual approval.
- 2026-06-01: splitting `Continue setup` and `Booking settings` created a trust problem: the app says page files are written locally, but the user cannot see where, reveal them in Finder, publish them, or verify the exact live artifact from the same surface.
- 2026-06-01: multiple appointment types are no longer just a static-template concern. The app needs a native editor because per-type hours, buffers, minimum notice, auto-acceptance, location, Google Meet, and share-link state are operational settings, not only Markdown copy.
- 2026-06-01: Google Meet creation is only available through the Google Calendar event-write path. The app must create Google-backed bookings with `conferenceData.createRequest`, pass `conferenceDataVersion=1`, and send attendee updates; Apple / iCloud bookings cannot auto-create a Meet without using Google Calendar as the accepted-booking calendar.
- 2026-06-01: Vercel automation is possible only if the user grants a Vercel token and chooses a scope/team/project name. The app verifies the deployed inbox by probing the relay contract after it deploys the bundled template.
- 2026-06-03: a follow-up UX audit found the booking flow still has two overlapping management surfaces: a four-step setup sheet and a six-section Booking workspace. The workspace is the better long-term IA, while the setup sheet should collapse into the workspace overview/readiness checklist.
- 2026-06-03: the browser-rendered generated public page is clear once a visitor reaches the details step, but its n=1 first viewport has too much empty space and the full IANA timezone select dominates DOM and screen-reader order for a secondary setting.
- 2026-06-03: macOS checkpoint capture succeeded for state/perf but rendered placeholder visual blocks in `window.png`, so this audit uses source-backed native findings plus browser-backed public-page findings rather than claiming a useful native screenshot.
- 2026-06-04: SwiftUI `openURL` is not a reliable macOS opener for generated local `file:` preview pages in this app. The preview action should regenerate files, then use `NSWorkspace.shared.open` for the local `index.html` with `openURL` only as fallback.
- 2026-06-04: the Publish pane was updating `bookingSetupSnapshot.lastMessage` after live verification, but that message was only surfaced elsewhere in the Booking workspace. Verification could fail correctly while appearing inert to the user on the pane where they clicked it.
- 2026-06-04: `Vercel scope` is platform vocabulary, not user vocabulary. In this flow it means the Vercel personal account or team slug that should own a CLI/app-managed deploy, and it should be optional when the user manually pastes an existing relay URL.
- 2026-06-04: target calendar is operational private state, not public appointment copy. Per-appointment Apple/Google target IDs must stay out of generated Pages artifacts and out of the public fingerprint so changing where bookings are written does not imply that the public page changed.
- 2026-06-04: a repo-relative `templates/booking-site/` path is not an end-user customization path for the Mac app. The app needs to bundle the seed template, create a user-editable copy in Application Support, and keep generated page files separate because generation replaces the publishable output folder.
- 2026-06-05: the Publish UI's `Folder` field makes a dedicated booking repository harder to reason about. A root-only repository contract is simpler, but repeated publishes still need to allow the app's own previously generated files so the user is not forced to recreate the repository after each upload.
- 2026-06-05: GitHub deploy keys fit the dedicated-repository contract better than a personal access token because the credential is attached to one repository. GitHub still documents important caveats: write-enabled deploy keys can push to the repo, do not expire, and are not tied to ongoing user membership, so the app must make revocation and key rotation clear.
- 2026-06-14: Booking appointment types are currently local-only `UserDefaults` data even though shared configuration already roams calendar/account setup. The editable `BookingSiteTemplate` folder and generated page-files folder are intentionally filesystem-local and should not enter the iCloud KVS payload.
- 2026-06-14: the prior 40-slot publishing cap conflicted with per-appointment booking windows because a busy user or multiple appointment types could exhaust the cap before the configured horizon. Publishing now emits every generated open slot for each active appointment type, bounded by the three-month per-type maximum.
- 2026-06-15: the App Store build can hit `xcrun: error: cannot be used within an App Sandbox` when launching `/usr/bin/git`. System Git on macOS is not a reliable runtime dependency for a sandboxed App Store app, and the deploy-key path also currently assumes system `ssh` and `ssh-keygen`.
- 2026-06-15: current Vercel REST docs support the user-facing shape requested here: project lookup accepts project `id` or `name`, environment variable upsert is available for a project `id` or `name`, and deployment creation accepts inline files for non-Git deployments. The existing relay template still depends on Vercel Blob for durable encrypted-envelope storage, so app-managed deploy can own relay secrets and code deployment but must surface missing Blob/project storage as a project setup health failure rather than asking users for an "inbox admin token."
- 2026-06-17: `BookingConfigurationError` had a custom `localizedDescription`, but audit paths receive it as erased `Error`; without `LocalizedError`, Swift bridged those failures to raw enum codes such as `Calendar_Busy_Sync.BookingConfigurationError error 2`.
- 2026-06-17: GitHub deploy-key public metadata can roam through shared Booking setup while the matching private key intentionally remains device-local in Keychain, so verify/publish must diagnose a missing local private key instead of implying a GitHub network failure.
- 2026-07-07: App Review flagged the macOS build that shipped copied Apple Git/SSH helper binaries for non-public or deprecated API references. App Store archives cannot ship those copied helpers; deploy-key publishing needs an in-process or otherwise review-safe publishing engine before it can be enabled in reviewed builds.

## Decision Log

- 2026-05-31: implement booking as a request workflow first. Auto-confirm is allowed only after the native app decrypts a request, validates the signed slot token, rechecks live calendars, and applies the user's appointment-type policy.
- 2026-05-31: store provider credentials, relay owner keys, GitHub publish tokens, and booking private keys only in platform secure storage. Generated Pages artifacts must contain only public keys, public config, public copy, public theme assets, opaque share IDs, and signed availability tokens.
- 2026-05-31: make Cloudflare Workers the recommended relay path because Workers KV, Durable Objects, Rate Limiting bindings, Turnstile validation, and Deploy to Cloudflare buttons cover the target shape with fewer moving parts.
- 2026-05-31: support Vercel as a second relay target using Vercel Functions plus Vercel Blob or another minimal Vercel-supported storage path, while documenting that Vercel's platform should still receive only encrypted blobs and metadata.
- 2026-05-31: make the static booking template a small, ordinary web project under a predictable directory with plain Markdown, CSS variables, and documented extension points so users can customize it with their own AI coding tools without touching Swift app internals.
- 2026-05-31: make the primary UX a resumable four-step setup assistant: Page, Publish, Relay, Test & Share. Each step gets one primary action, inline validation, a visible completion state, and a safe test path.
- 2026-05-31: on macOS, expose booking as a stable Settings toolbar pane plus a larger setup window when the assistant is active. On iPhone, use a single navigation flow with large tap targets and no dependency on side-by-side layout. On iPad, adapt to a split view when width allows.
- 2026-05-31: advanced setup options such as custom relay compatibility, local-git publishing, token scopes, slot-token TTLs, proof-of-work difficulty, and template protocol internals are hidden behind clearly labeled disclosure controls or an Advanced section.
- 2026-05-31: native app iconography uses SF Symbols with visible text labels for all non-obvious actions. The generated public web template must not depend on SF Symbols; it should use text first and a small vendored open-source icon subset only where icons clarify scanning.
- 2026-05-31: all booking UI copy is sentence case, active voice, specific about the next action, and stored in a small copy registry instead of scattered string literals.
- 2026-05-31: keep the first implementation as a safe vertical slice instead of adding live GitHub token storage and automatic calendar-write approval in the same change. The checked-in code now defines the privacy-critical contracts and templates; live publishing and the platform-adaptive setup assistant should build on those contracts in later milestones.
- 2026-06-01: keep the native publish button in this slice as either local page-file generation or published-page verification. It does not yet store a GitHub token or write to a repository, preserving the open-source secret boundary until the dedicated publishing milestone can add Keychain-backed token storage and explicit least-privilege validation.
- 2026-06-01: import and approval use the admin-token relay API, but the lightweight inbox check remains limited to public `/healthz` so routine setup diagnostics never require an admin secret.
- 2026-06-01: publish the live smoke site to `https://moorage.github.io/booking-test/` and keep the Vercel relay at `https://live-booking-relay-vercel.vercel.app` for this test run. The live request was deleted after verification.
- 2026-06-01: add a narrow `--booking-dry-run-on-launch` harness flag for signed local validation. It refreshes Apple Calendar access, generates booking page files from local busy intervals, and exits without running the full Google restore/sync startup path.
- 2026-06-01: make the settings primary setup button open a concrete setup sheet instead of performing hidden work. The sheet owns the Page, Publish, Inbox, and Test actions, while the compact settings actions remain repair/shortcut controls.
- 2026-06-01: keep this setup sheet as an incremental macOS/iPadOS/iOS-safe SwiftUI flow inside the existing settings shell. The larger production assistant can still promote this into a dedicated window or platform-specific navigation surface, but the primary button must never be inert.
- 2026-06-01: make `Send test request` use the same privacy boundary as the public web page: fetch the published public config and availability, encrypt a synthetic Matt Moore request locally with P-256 ECDH/AES-GCM, and POST only the encrypted envelope to the configured inbox.
- 2026-06-01: store the booking private key, inbox ID, slot signing secret, and inbox admin token in platform secure storage through a booking-specific secret store. Public artifacts receive only the public P-256 key, opaque inbox/share IDs, and signed slot tokens.
- 2026-06-01: implement manual approval before auto-confirm. Imported requests become approve-able only after local decryption, slot-token verification, expiry checks, and a live selected-Apple-calendar availability recheck.
- 2026-06-04: drive prominent Booking Page/Publish buttons from `BookingSetupSnapshot` lifecycle semantics instead of hard-coding a blue `Generate page files` or disabled blue `Publish page`. In the uploaded/waiting-for-Pages state, `Verify live page` is the primary action.
- 2026-06-04: make accepted-booking calendars appointment-type settings. Older saved global booking target settings remain a fallback for compatibility, but new appointment types get an explicit target and the editor surfaces missing-target warnings alongside the appointment location policy.
- 2026-06-01: first calendar-write support targets the selected Apple / iCloud calendar. The written event is busy, contains the visitor details needed for the appointment request, and is distinct from app-managed mirror events.
- 2026-06-01: treat booker and guest emails as invite recipients only inside the native app after local decryption. Google booking writes should send those recipients through Google Calendar `attendees`; iCloud booking writes should produce a local `.ics` invite file instead of trying unsupported EventKit attendee mutation.
- 2026-06-01: prepare the decline notice before deleting the encrypted relay request. If relay cleanup fails after the notice was prepared, the request still becomes declined and the audit trail records the cleanup issue, avoiding duplicate provider emails or duplicate decline files on retry.
- 2026-06-01: keep booking credentials and URLs in `Booking settings` instead of the main Booking panel. The main panel remains a status and active-inbox view; approved and declined requests stay accessible through request history.
- 2026-06-01: use an `appointment` query parameter for appointment-type deep links. The static page matches it against either appointment slug or ID and preselects the matching card.
- 2026-06-01: make automatic acceptance a global Booking setting in this slice, default off. It should approve only newly imported pending requests and leave unavailable or failed requests in the active inbox for review.
- 2026-06-01: replace the split setup/settings model with one `Booking` workspace that owns setup, settings, publishing, request inbox, and history. The steady-state pane can stay compact, but all booking configuration must be reachable from that pane without a second, duplicate settings sheet.
- 2026-06-01: make the local page-file folder a first-class configuration value. The app shows the resolved path, has `Open in Finder`, `Change folder...`, `Generate page files`, `Preview local page`, and `Publish to GitHub Pages` actions, and treats "files written locally" as incomplete until the user can inspect and publish them.
- 2026-06-01: for app-managed GitHub Pages publishing, prefer repository contents commits for generated static files and use Pages API only when enabling or changing Pages settings. The required user inputs are owner/repo, branch, Pages URL, and a fine-grained token stored in Keychain.
- 2026-06-05: remove the GitHub publishing path/folder setting. The app treats a GitHub Pages repository as dedicated to the booking page, publishes to repository root, and blocks upload if root contains files outside the current generated site artifact set.
- 2026-06-05: migrate GitHub Pages publishing to deploy keys only. The app will no longer store or ask for a GitHub token for normal publishing; it will generate a repository-specific SSH keypair locally, store the private key in secure storage, show the public key for the user to add as a write-enabled GitHub deploy key, and publish by committing to the repository root over SSH.
- 2026-06-14: add a non-secret `SharedBookingConfiguration` to the iCloud shared settings payload. It carries native Booking setup such as page/inbox URLs, repository/branch, Vercel metadata, profile/theme fields, selected appointment type, automatic approval, and appointment-type definitions. It does not carry Vercel account tokens, inbox admin tokens, booking private/signing keys, GitHub deploy-key private keys, generated page-file paths, or editable HTML/CSS/template file contents.
- 2026-06-14: appointment types own the booking availability horizon. The native editor offers up to three months, older saved appointment types default to 14 days, generated public config includes the horizon, and the background publish loop regenerates and pushes all active appointment-type availability on each poll when GitHub publishing is configured.
- 2026-06-15: keep the deploy-key model, but make the runtime Git/SSH stack app-owned. The production app must not call `/usr/bin/git`, `/usr/bin/ssh`, or `/usr/bin/ssh-keygen`; the short-term code path resolves bundled helpers and fails clearly when a build is missing them, while the longer-term implementation can replace the helper binaries with an in-process libgit2-backed publisher.
- 2026-06-18: `/usr/bin/git` is only an `xcrun` shim on the current macOS environment, so copying it into the app would still depend on Command Line Tools. Xcode's real Git binary can run the app's clone/add/commit/push/ls-remote command set from a minimal bundled `GIT_EXEC_PATH` containing a `git` symlink back to `booking-git`.
- 2026-06-18: Xcode user-script sandboxing denied recursive `git-core` packaging even with a directory output path. The app target now disables user-script sandboxing, while the packaging script remains constrained to explicit Xcode and system helper sources plus the app executable directory destination.
- 2026-07-07: remove copied helper binaries from App Store archive/install builds instead of trying to repackage Apple command-line tools into a reviewed app. Local/debug builds may still exercise the helper path, but App Store publishing should stay unavailable until replaced with a review-safe implementation.
- 2026-06-01: for app-managed Vercel setup, require a Vercel account token, account scope/team slug when applicable, project name, allowed GitHub Pages origin, and generated inbox/admin secrets stored in Keychain. A no-token self-deploy path remains supported by pasting the relay URL and admin token.
- 2026-06-15: for Vercel setup, the primary user contract is `Vercel token` plus `Vercel project ID or name`, with optional team ID/slug only when the project belongs to a team. The app generates and stores `INBOX_ADMIN_TOKEN` in Keychain, upserts relay environment variables, deploys/redeploys the bundled Vercel template, and saves the returned production URL as the inbox URL.
- 2026-06-17: Vercel's current CLI provisions Blob with `POST /v1/storage/stores/blob` and connects a store to a project with `POST /v1/storage/stores/{storeId}/connections`; the app can reuse those API contracts instead of requiring a manual dashboard storage step.
- 2026-06-17: app-managed Vercel deploy now resolves the project, reuses an already-connected Blob store when present, otherwise creates a public Blob store and connects it to production before creating the relay deployment. The app does not persist the Blob token locally; Vercel injects it into the project environment.
- 2026-06-01: Google Meet is an appointment-type location option, but enabling it is gated on a Google accepted-booking calendar with write access and a calendar that supports `hangoutsMeet`; otherwise the UI explains the dependency and keeps the option disabled.
- 2026-06-02: the first multiple appointment-type editor exposed correct fields but used raw text and stepper controls that make weekly hours hard to trust. The editor needs to show appointment types as shareable cards first, then edit one selected type with disclosure sections and day-by-day hour rows.
- 2026-06-02: the macOS `NavigationStack` plus segmented `Picker` inside the sheet could reserve large vertical bands before and after the selector. A custom sheet header and selector make the layout deterministic.
- 2026-06-02: Computer Use was requested for visual inspection, but the local Computer Use MCP repeatedly returned `codex app-server exited before returning a response`. Validation fell back to source inspection, build, and focused tests.
- 2026-06-03: keep the UX/IA report in `docs/ideas/backlog/booking-appointment-management-ux-ia-audit.md` instead of immediately changing booking code. The report is shaping work for the next Booking workspace milestone and avoids expanding the already-large active implementation diff.

## Outcomes & Retrospective

The first implementation establishes the privacy boundary in code and docs:

- native booking strings and SF Symbols are centralized in `BookingCopy.swift` and `BookingIconography.swift`
- Markdown-backed appointment/profile parsing rejects secret-looking values before publishing
- signed public slot claims and public artifact generation avoid provider IDs and raw busy intervals
- imported encrypted request envelopes can be decrypted locally with P-256 ECDH/AES-GCM and deduped in a local request ledger
- native settings can generate local public page files, persist booking page/inbox URLs, verify the public page over HTTPS, and check the inbox health endpoint
- semantic booking IDs and signed slot tokens now encode to the browser/relay JSON contract as strings
- availability suppression uses half-open interval overlap semantics so valid adjacent slots are not hidden, and appointment buffers now expand real busy intervals before slot publication
- signed app draft generation can derive public open slots from the currently selected Apple / iCloud calendar without publishing calendar IDs, event IDs, raw busy blocks, account emails, or provider tokens
- the primary setup button now opens an explicit setup flow with Page, Publish, Inbox, and Test steps instead of silently running the old page-file/verify path
- the setup flow now opens on the current actionable step each time it is launched, so a ready configuration lands on Test and share instead of sending the user back to Page
- first-run setup can generate page files from a clean `notStarted` snapshot; the stale `hasStarted` disablement was removed
- the native Test action now sends a real browser-style encrypted request through the published site configuration and configured inbox, including compatibility with browser-standard JWK boolean values
- app-generated drafts now reuse a persisted private key, inbox ID, and slot-signing secret so later inbox imports can decrypt requests and verify signed slot claims
- the Booking settings UI now accepts an inbox admin token, imports encrypted request envelopes from the configured relay, shows locally decrypted requests, and supports approve/decline actions
- imported requests are rechecked against the selected Apple / iCloud calendar before approval, and approving writes a busy booking event into that calendar
- relay cleanup happens after approval/decline; if cleanup fails after a successful calendar write, the request stays approved and the audit trail records the inbox cleanup issue
- the public GitHub Pages template encrypts visitor details before posting to the inbox
- Cloudflare and Vercel relay templates implement a blind encrypted inbox API with abuse controls
- the live Vercel relay accepted an encrypted request from the Pages origin, listed only ciphertext and envelope metadata through the admin API, and deleted the test record
- the live Pages test site served 40 open slots generated from the user's current iCloud calendar, and a live encrypted request for the first slot returned no visitor plaintext through the relay admin list API before deletion
- the existing settings shell now shows a Booking section with setup state, automation IDs, shortcut actions, and a working setup sheet
- manual macOS validation confirmed the debug app opens without the unsigned Google keychain hang, the setup sheet reaches Test and share from the ready state, and the live Vercel inbox accepts the encrypted test request from the app
- browser-facing validation confirmed the GitHub Pages form itself can submit a request from Chrome and reach its success state after encrypting and posting to the configured inbox
- focused AppModel validation confirmed a persisted-key request can be imported through the relay API, decrypted, approved after live-availability recheck, written to the Apple Calendar provider boundary, and deleted from the encrypted inbox
- live app validation confirmed the same flow against `https://moorage.github.io/booking-test/` and `https://live-booking-relay-vercel.vercel.app`: the signed app imported two encrypted requests, approved the Matt Moore / `matt@alumni.ucsd.edu` request for Jun 2, 2026 09:00-09:30 PDT, wrote it to the selected `Matt - iCloud` calendar, and reduced the live relay inbox from two records to one by deleting the approved record
- the public page now uses a calendar-first booking flow: available days receive a visible background, today gets a persistent marker, times render as buttons, selecting a time reveals an animated `Next` button, and the details screen supports back navigation plus additional guest email fields
- the public page now disables previous/next month arrows when the selected appointment has no bookable slots in that direction, with disabled accessibility labels so visitors do not navigate into empty future months
- imported booking requests now preserve the public page's additional guest emails after local decryption, normalize/dedupe the booker plus guests, and reuse that recipient list for native calendar side effects only
- Google booking writes now create a private booking event with populated Google Calendar `attendees` and `sendUpdates=all`, so the booker and additional guests receive provider-managed invitations
- iCloud booking approvals now write the busy EventKit event and create a local RFC 5545 `.ics` invite file with `ATTENDEE` lines for the booker and guests, avoiding unsupported EventKit attendee mutation
- declining a Google-backed booking request now creates a private transparent Google Calendar event with the owner attendee marked declined, the booker and guests included as attendees, and `sendUpdates=all`
- declining an iCloud-backed booking request now saves a local RFC 5545 decline reply `.ics` file with the owner marked `DECLINED` and the booker plus guests populated as invitees
- the public booking page now ships the app icon as `assets/app-icon.png` and uses it as the default Open Graph image, Twitter image, favicon, and Apple touch icon
- appointment type Markdown now supports per-type weekly hours such as `weekly_hours: mon=09:00-16:30;tue=09:00-16:30;fri=closed`, and generated app/site availability uses those hours instead of a hidden global weekday default
- the native Booking panel now opens a dedicated `Booking settings` sheet for page URL, inbox URL, and admin token, shows only non-approved/non-declined requests in the active inbox, keeps all imported requests available in `View history`, and uses `Generate page files` / `Refresh page files` instead of draft and dry-run copy
- the native Booking page row now has an appointment-type picker plus open/copy controls; copied links preserve the base page query string and append `appointment=<slug>`, and the static page preselects that appointment type when opened. The live `moorage/booking-test` page serves the deep-link-aware JavaScript from commit `b262a7a`.
- `Booking settings` now includes `Automatically accept requests`; when enabled, import attempts to approve newly imported requests through the same local calendar-write path as the manual `Approve` button and reports how many were automatically accepted
- `Booking settings` now also names the selected calendar target for accepted bookings and exposes Apple/iCloud connect, Google account add, and calendar picker controls there so automatic acceptance is not enabled against a hidden destination
- the public booking page now updates selected time rows in place instead of rebuilding the scrollable time list, so clicking a lower time slot keeps the visitor's viewport anchored; the live `moorage/booking-test` page serves the fix from commit `436d833`
- the public booking page's additional guest fields are now removable, so visitors can correct the invitee list before submitting; successful submissions also clear dynamic guest rows
- the public booking details step now shows `← Back` above the `Enter details` heading, making the navigation target clearer before the visitor starts filling the form
- the public booking details step now shows the selected appointment time as a larger summary above `Name` and `Email`, instead of only using the small status line below the form
- the native appointment-type workspace now uses compact selectable appointment cards with copy/open/more actions, and edits one selected type through disclosure sections for duration, location, availability, and auto-acceptance
- weekly hours now use visual day rows with add/remove time windows and menu-based start/end pickers instead of a raw serialized `weekly_hours` text field
- booking request form notes are labeled `Notes:` in calendar event descriptions, Google Calendar event payloads, and generated iCloud `.ics` files, with focused tests covering both provider paths
- the Booking settings sheet now uses a compact local header with Done, a custom segmented section selector, and top-pinned scroll content to avoid the large blank gaps seen in the macOS sheet
- GitHub Pages publishing now assumes a dedicated empty repository, publishes generated files at repository root, and blocks upload when recursive root inspection finds files outside the generated artifact set. The Publish workspace no longer stores or renders a remote folder field.
- iCloud shared settings now include non-secret native Booking setup through `SharedBookingConfiguration`: appointment type definitions, page/inbox URLs, repository and branch, Vercel metadata, native public profile/theme fields, selected appointment type, and automatic-approval preference. The sync path intentionally excludes Vercel account tokens, inbox admin tokens, booking private/signing keys, GitHub deploy-key private keys, generated page-file paths, and editable HTML/CSS/template files.
- Appointment types now include `availabilityHorizonDays`; the Booking workspace exposes it as `Show availability`, validates a maximum of three months, and public availability generation emits all open slots for every active appointment type across its configured horizon on manual publish and each background poll publish.
- App-managed Vercel inbox deployment now owns the storage setup needed for a ready inbox: it resolves the project by ID/name, reuses any connected Blob store, creates and connects a public Blob store to production when absent, then deploys the relay and verifies `/healthz`.
- Booking configuration failures now conform to `LocalizedError`, so GitHub deploy-key verification and Pages publishing audit entries show actionable messages instead of raw enum codes.
- Missing local GitHub deploy-key private keys and missing bundled Git/SSH helpers now appear in the Booking workspace action message, not only in the audit trail, so recovery points to regenerating the local key or installing an app build with the packaged helpers.
- local macOS builds can package `booking-git`, `booking-ssh`, `booking-ssh-keygen`, and a minimal `booking-git-core` exec-path directory beside the app executable. App Store archive/install builds intentionally omit those copied Apple helper binaries after App Review flagged the submitted build for non-public/deprecated API references; the GitHub publisher uses the existing missing-helper error path in reviewed builds until a review-safe publishing engine replaces the helper bundle.

Remaining work for a production-ready booking release is live app-side GitHub publishing/token storage, promotion of the setup sheet into the full platform-adaptive assistant described above, persistent local request-ledger storage across launches, cleanup controls for stale duplicate requests, per-appointment automatic-acceptance policy, clearer UI affordances for opening iCloud `.ics` artifacts, and investigation of the current local macOS UI-test runner stall even though manual accessibility validation covers the setup flow.

This follow-up will also make the appointment-type workspace match the reference booking-product flow: appointment cards remain compact and shareable, editing opens one selected type, duration/location/availability use disclosure sections, weekly hours are edited visually rather than through serialized Markdown, and visitor notes are explicitly labeled as notes in every calendar payload generated from a booking request.

## Context and Orientation

Relevant existing files:

- `README.md`
- `ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/product-specs/calendar-sync.md`
- `docs/harness.md`
- `docs/debug-contracts.md`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Sync/BusyMirrorSyncModels.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Sync/BusyMirrorSyncPlanner.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleCalendarService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Apple/AppleCalendarService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`

New likely file areas:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Markdown/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Crypto/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Relay/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Publishing/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Onboarding/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Platform/macOS/Booking/`
- `Calendar Busy Sync/Calendar Busy Sync/App/Platform/iOS/Booking/`
- `Calendar Busy Sync/Calendar Busy SyncTests/BookingTests.swift`
- `Fixtures/booking/`
- `templates/booking-site/`
- `templates/booking-relay/cloudflare/`
- `templates/booking-relay/vercel/`
- `docs/product-specs/privacy-first-booking.md`
- `docs/self-hosting/booking-pages-github.md`
- `docs/self-hosting/encrypted-relay-cloudflare.md`
- `docs/self-hosting/encrypted-relay-vercel.md`
- `docs/self-hosting/ai-template-customization.md`
- `docs/self-hosting/videos/README.md`
- `scripts/build-booking-site`
- `scripts/test-booking-site`
- `scripts/test-booking-relay-cloudflare`
- `scripts/test-booking-relay-vercel`
- `scripts/capture-booking-onboarding-videos`

External references to verify during implementation:

- GitHub Pages static publishing and source configuration: `https://docs.github.com/github/working-with-github-pages/creating-a-github-pages-site`
- GitHub fine-grained personal access token setup: `https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token`
- GitHub repository contents API for publishing generated files: `https://docs.github.com/en/rest/repos/contents`
- GitHub deploy key setup and tradeoffs: `https://docs.github.com/developers/overview/managing-deploy-keys/`
- GitHub deploy-key API reference, only for confirming permissions and manual setup constraints: `https://docs.github.com/en/rest/deploy-keys/deploy-keys`
- Cloudflare Deploy to Cloudflare buttons: `https://developers.cloudflare.com/workers/platform/deploy-buttons/`
- Cloudflare Workers secrets: `https://developers.cloudflare.com/workers/configuration/secrets/`
- Cloudflare Workers Rate Limiting binding: `https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/`
- Cloudflare Turnstile server-side validation: `https://developers.cloudflare.com/turnstile/get-started/server-side-validation/`
- Vercel Deploy Button: `https://vercel.com/docs/deployments/deploy-button`
- Vercel Deploy Button environment variables: `https://vercel.com/docs/deploy-button/environment-variables`
- Vercel environment variables: `https://vercel.com/docs/projects/environment-variables`
- Vercel Blob client uploads: `https://vercel.com/docs/vercel-blob/client-upload`
- Vercel REST API project creation: `https://vercel.com/docs/rest-api/reference/endpoints/projects/create-a-new-project`
- Vercel REST API environment variables: `https://vercel.com/docs/rest-api/reference/endpoints/projects/create-one-or-more-environment-variables`
- Vercel REST API deployments: `https://vercel.com/docs/rest-api/reference/endpoints/deployments/create-a-new-deployment`
- Google Calendar event creation and Meet conference data: `https://developers.google.com/workspace/calendar/api/guides/create-events`
- Google Calendar events insert reference: `https://developers.google.com/workspace/calendar/api/v3/reference/events/insert`
- Google Calendar attendee invitations: `https://developers.google.com/calendar/api/concepts/inviting-attendees-to-events`
- Apple HIG onboarding: `https://developer.apple.com/design/human-interface-guidelines/onboarding`
- Apple HIG privacy: `https://developer.apple.com/design/human-interface-guidelines/privacy`
- Apple HIG settings: `https://developer.apple.com/design/human-interface-guidelines/settings`
- Apple HIG sheets: `https://developer.apple.com/design/human-interface-guidelines/sheets`
- Apple HIG disclosure controls: `https://developer.apple.com/design/human-interface-guidelines/disclosure-controls`
- Apple HIG entering data: `https://developer.apple.com/design/human-interface-guidelines/entering-data`
- Apple HIG layout: `https://developer.apple.com/design/human-interface-guidelines/layout`
- Apple HIG menu bar: `https://developer.apple.com/design/human-interface-guidelines/the-menu-bar`
- Apple HIG writing: `https://developer.apple.com/design/human-interface-guidelines/writing`
- Apple HIG labels: `https://developer.apple.com/design/human-interface-guidelines/labels`
- Apple HIG buttons: `https://developer.apple.com/design/human-interface-guidelines/buttons`
- Apple HIG icons: `https://developer.apple.com/design/human-interface-guidelines/icons`
- GOV.UK writing for user interfaces: `https://www.gov.uk/service-manual/design/writing-for-user-interfaces`
- GOV.UK style guide: `https://www.gov.uk/guidance/style-guide`
- Microsoft Windows app writing style: `https://learn.microsoft.com/en-us/windows/apps/design/style/writing-style`
- Microsoft Writing Style Guide: `https://learn.microsoft.com/en-gb/style-guide/welcome/`
- Nielsen Norman Group usability heuristics: `https://www.nngroup.com/articles/ten-usability-heuristics/`
- Shopify Polaris icon creation guidance: `https://polaris-react.shopify.com/design/icons/creating-icons`
- IBM Carbon icon usage guidance: `https://carbondesignsystem.com/elements/icons/usage/`
- Atlassian Design System: `https://atlassian.design/design-system/`

Roundtable synthesis:

- Security: all provider tokens and calendar-derived private data stay local. Public artifacts use opaque, expiring, signed slot capabilities and public encryption keys only. The relay is blind and can only enforce generic abuse controls.
- UX: setup must be wizard-driven with copyable snippets, "why this is needed" explanations, and recovery paths for deploy-key rotation, repo migration, and relay redeploy.
- Architecture: booking should sit beside the existing busy-mirror sync domain. It may reuse normalized busy occupancy, but it must not leak source-event identity into static artifacts.
- Reliability: the app must tolerate offline periods. Requests queue in the relay, expire deterministically, dedupe by request ID, and are revalidated against live calendars before any calendar write.
- Open-source ergonomics: templates and relay code should be plain, inspectable, and forkable. Secrets are user-provided at setup time, never embedded in template repos, docs, screenshots, or checked-in examples.

HIG-informed UX principles:

- Onboarding is optional, fast, and task-based. The user should be able to skip setup, return later, and resume at the exact incomplete step.
- Each step teaches through doing:
  - generate page files and preview them
  - validate GitHub publishing with a page-file preflight
  - validate the relay with a health check
  - submit a synthetic encrypted booking request and approve it locally
- Context-specific tips appear next to the relevant control instead of in a long introduction. Use TipKit-style inline tips where possible.
- Settings stay stable and compact. The permanent settings pane shows status, links, and repair actions; the guided assistant handles first-run setup.
- Advanced controls stay behind disclosure groups and never block the default path.
- Sensitive-entry screens explain why the app asks for a deploy key, token, or URL immediately before the field, store private values securely, and provide a clear rotate/revoke path.
- On macOS, avoid putting critical progress or primary actions only at the bottom of a window. Keep step status visible in a sidebar or top summary and repeat the primary action near the active content.
- On iOS, avoid stacked sheets for setup. Use a navigation flow with Back/Cancel affordances and a single primary action per screen.
- Alerts are reserved for destructive or blocking states. Routine validation, warnings, and recovery guidance use inline status rows.
- The setup flow should never ask users to memorize provider steps. It should provide buttons that open the exact provider page, copy the exact value needed, and return to a validation control.

Copy and iconography specification:

- Copy principles:
  - use sentence case for headings, labels, buttons, and menu items, except product names such as GitHub Pages, Cloudflare, Vercel, Codex CLI, and Claude Code CLI
  - start button labels with a verb when the action changes state or opens a task
  - use direct "you" language when explaining what the user needs to do
  - avoid jokes, marketing phrasing, and vague reassurance in setup, error, and privacy copy
  - avoid "please", "note", "oops", "invalid", "failed", "ciphertext", "payload", "CORS", "TTL", "webhook", and "relay" in primary UI unless the user opens Advanced
  - use "request inbox" in primary UI; use "encrypted relay" in technical docs and Advanced
  - use "request" until the native app writes a calendar event; use "booking" only after approval or auto-confirmation
  - make form labels persistent; placeholder text can show examples only
  - every error message states the problem and the next repair action in plain language
  - no copy may claim a time is booked until live availability has been rechecked and the calendar write has succeeded
- Native icon rules:
  - use SF Symbols for native macOS, iPhone, and iPad UI
  - pair icons with visible labels for setup steps, sidebar items, cards, buttons, and non-obvious actions
  - allow icon-only buttons only for conventional compact controls, and only with tooltips plus accessibility labels
  - use one symbol metaphor consistently across the feature; do not reuse the same icon for different meanings in the same context
  - use monochrome system rendering for routine settings actions, hierarchical rendering for status, and avoid multicolor symbols except provider-branded badges already present in the app
  - if a listed SF Symbol is unavailable on the minimum supported OS, use the listed fallback symbol rather than inventing a custom icon
- Public web icon rules:
  - the generated GitHub Pages site should be text-first
  - do not use SF Symbols in public web artifacts unless licensing is reviewed and explicitly approved
  - if icons are included, vendor a small open-source SVG subset, keep one stroke weight, and provide accessible names or hide decorative icons from assistive technologies

Native app screen copy and icons:

| Screen or element | Primary icon | Fallback icon | Exact visible copy |
| --- | --- | --- | --- |
| Settings toolbar item | `calendar.badge.plus` | `calendar` | `Booking` |
| Booking settings title | `calendar.badge.plus` | `calendar` | `Booking` |
| Booking settings subtitle | none | none | `Let people request time without sharing your calendars.` |
| Booking workspace overview | `calendar.badge.plus` | `calendar` | `Overview` |
| Appointment types tab | `list.bullet.rectangle` | `list.bullet` | `Appointment types` |
| Page files tab | `folder` | `doc.text` | `Page files` |
| Publish tab | `globe` | `square.and.arrow.up` | `Publish` |
| Inbox tab | `tray` | `lock` | `Request inbox` |
| History tab | `clock.arrow.circlepath` | `clock` | `History` |
| Not set up empty state | `calendar.badge.plus` | `calendar` | Title: `Set up a booking page`; Body: `Create a public page, connect a private request inbox, and test the flow before you share a link.`; Primary action: `Set up booking` |
| Incomplete setup state | `arrow.clockwise` | `clock` | Title: `Finish booking setup`; Body: `Continue from the last completed step.`; Primary action: `Continue setup` |
| Ready state | `checkmark.circle` | `checkmark` | Title: `Booking is ready`; Body: `Your page is published and this app can receive encrypted requests.` |
| Booking page status card | `globe` | `link` | Title: `Booking page`; Statuses: `Not published`, `Published`, `Needs publish`, `Publish failed` |
| Request inbox status card | `tray` | `lock` | Title: `Request inbox`; Statuses: `Not connected`, `Connected`, `Needs check`, `Cannot reach inbox` |
| Pending requests card | `tray.full` | `tray` | Title: `Requests`; Empty: `No booking requests`; Count: `%d pending` |
| Copy booking link | `link` | `doc.on.doc` | `Copy booking link` |
| Open booking page | `arrow.up.right.square` | `globe` | `Open booking page` |
| Publish page | `square.and.arrow.up` | `arrow.up.doc` | `Publish page` |
| Open page files folder | `folder` | `doc.text` | `Open in Finder` |
| Change page files folder | `folder.badge.gearshape` | `folder` | `Change folder...` |
| Preview local page | `eye` | `doc.text.magnifyingglass` | `Preview local page` |
| Publish to GitHub Pages | `square.and.arrow.up` | `arrow.up.doc` | `Publish to GitHub Pages` |
| Verify live page | `checkmark.seal` | `checkmark.circle` | `Verify live page` |
| Check inbox | `arrow.clockwise` | `tray` | `Check inbox` |
| Deploy Vercel inbox | `network` | `tray` | `Set up Vercel inbox` |
| Verify Vercel inbox | `checkmark.seal` | `checkmark.circle` | `Verify inbox` |
| Rotate inbox | `arrow.triangle.2.circlepath` | `arrow.clockwise` | `Rotate inbox` |
| Advanced booking settings | `gearshape` | `slider.horizontal.3` | `Advanced booking settings` |

Setup assistant copy and icons:

| Step | Primary icon | Heading | Body copy | Primary action | Secondary actions |
| --- | --- | --- | --- | --- | --- |
| Page | `doc.text` | `Create your booking page` | `Choose what people can request. Your calendar details stay on this device.` | `Generate page files` | `Preview page`, `Edit appointment types` |
| Publish | `globe` | `Publish with GitHub Pages` | `The app publishes only public page files and signed open slots.` | `Publish page` | `Generate deploy key`, `Copy public key`, `Verify deploy key`, `Refresh page files` |
| Relay | `tray` | `Connect a private request inbox` | `The inbox stores encrypted requests until this app reads them.` | `Check inbox` | `Deploy Cloudflare inbox`, `Deploy Vercel inbox`, `Copy allowed website`, `Paste inbox URL` |
| Test & Share | `paperplane` | `Test and share` | `Send a test request before you share the link.` | `Send test request` | `Import requests`, `Approve test request`, `Copy booking link`, `Open booking page` |

Setup field labels and help text:

| Field | Label | Placeholder or example | Help text |
| --- | --- | --- | --- |
| Public profile name | `Public name` | `Sam Rivera` | `This name appears on your booking page.` |
| Page title | `Page title` | `Request time with Sam` | `Use the words people expect to see when they open the link.` |
| Appointment type name | `Appointment name` | `Intro call` | `People choose this before they pick a time.` |
| Link name | `Link name` | `intro-call` | `This appears in the share URL for this appointment type.` |
| Duration | `Duration` | `30 minutes` | `The page only shows times that fit this duration and your buffers.` |
| Minimum notice | `Minimum notice` | `24 hours` | `Hide times that are too soon to review.` |
| Buffer before | `Buffer before` | `10 minutes` | `Keep time free before each request.` |
| Buffer after | `Buffer after` | `10 minutes` | `Keep time free after each request.` |
| Weekly hours | `Weekly hours` | `Monday-Friday, 9:00 AM-4:30 PM` | `People can request only during these hours.` |
| Location | `Location` | `Google Meet` | `Choose what gets added to accepted bookings.` |
| Create Google Meet | `Create Google Meet` | none | `Available when accepted bookings are written to a Google calendar.` |
| Auto-accept this type | `Automatically accept this appointment type` | none | `The app still rechecks availability before writing the event.` |
| Page files folder | `Page files folder` | none | `These are the public files the app can publish to GitHub Pages.` |
| GitHub repository | `GitHub repository` | `owner/repo` | `Use a dedicated empty repository for this booking page.` |
| GitHub branch | `Publishing branch` | `main` | `The app writes page files to this branch.` |
| GitHub deploy key | `Deploy key` | none | `Add this public key to the repository with write access.` |
| Pages URL | `Booking page URL` | `https://owner.github.io/repo/` | `This is the public page people open.` |
| Allowed website | `Allowed website` | `https://owner.github.io` | `The inbox accepts requests only from this website.` |
| Share link name | `Link name` | `Intro call` | `Use a name you can recognize later.` |
| Vercel token | `Vercel token` | none | `Stored in Keychain and used only to create or update your request inbox.` |
| Vercel team | `Vercel team ID or slug (optional)` | `team_...` or `team-slug` | `Use this only when the project belongs to a Vercel team.` |
| Vercel project | `Vercel project ID or name` | `prj_...` or `booking-inbox` | `The app creates or updates this Vercel project.` |

Provider card copy:

| Provider | Icon | Badge | Body | Primary action | Secondary action |
| --- | --- | --- | --- | --- | --- |
| Cloudflare | `cloud` | `Recommended` | `Good default for a small encrypted request inbox with rate limits.` | `Deploy Cloudflare inbox` | `Open Cloudflare guide` |
| Vercel | `network` | `Alternative` | `Use this if you already prefer Vercel for small web services.` | `Deploy Vercel inbox` | `Open Vercel guide` |
| Custom compatible relay | `link` | `Advanced` | `Use an endpoint that implements the same encrypted inbox API.` | `Use custom inbox` | `View API contract` |

Validation and status copy:

| State | Icon | Copy |
| --- | --- | --- |
| GitHub deploy key ready | `checkmark.circle` | `Deploy key can write to this repository.` |
| GitHub deploy key missing | `exclamationmark.triangle` | `Add the public key to the repository with write access, then verify again.` |
| GitHub repo not found | `exclamationmark.triangle` | `Repository not found. Check the owner and repository name.` |
| Pages not enabled | `exclamationmark.triangle` | `GitHub Pages is not enabled for this repository. Open GitHub Pages settings, then validate again.` |
| Page files ready | `doc.text` | `Page files ready. Review them before publishing.` |
| Page files folder ready | `folder` | `Page files are ready in this folder.` |
| Page files folder missing | `exclamationmark.triangle` | `Choose a page files folder before publishing.` |
| Publish succeeded | `checkmark.circle` | `Booking page published.` |
| Publish failed | `exclamationmark.triangle` | `Could not publish the page. Check the deploy key and try again.` |
| Live page verified | `checkmark.circle` | `Live page matches the latest page files.` |
| Live page stale | `exclamationmark.triangle` | `Live page is older than your page files. Publish again.` |
| Inbox reachable | `checkmark.circle` | `Inbox is reachable.` |
| Inbox unreachable | `exclamationmark.triangle` | `Cannot reach the inbox. Check the URL, then try again.` |
| Allowed website mismatch | `exclamationmark.triangle` | `Inbox rejected the booking page. Copy the allowed website and update the inbox settings.` |
| Vercel token valid | `checkmark.circle` | `Token works for this Vercel project.` |
| Vercel token rejected | `exclamationmark.triangle` | `Token does not work for this Vercel project. Check the token, then validate again.` |
| Vercel deployment ready | `checkmark.circle` | `Vercel inbox is deployed and reachable.` |
| Google Meet unavailable | `exclamationmark.triangle` | `Choose a Google calendar before creating Google Meet links.` |
| Test request sent | `paperplane` | `Test request sent.` |
| Test request imported | `tray.and.arrow.down` | `Test request received and decrypted.` |
| Test request missing | `exclamationmark.triangle` | `No test request found yet. Check the inbox, then import again.` |
| Slot still open | `checkmark.circle` | `This time is still open.` |
| Slot no longer open | `exclamationmark.triangle` | `This time is no longer open. Decline the request or suggest another time.` |
| Request expired | `clock` | `Request expired. Ask the person to choose another time.` |
| Calendar write succeeded | `checkmark.circle` | `Booking added to your calendar.` |
| Calendar write failed | `exclamationmark.triangle` | `Could not add the booking. Check calendar access, then try again.` |

Pending request workflow copy and icons:

| Element | Icon | Copy |
| --- | --- | --- |
| Requests screen title | `tray` | `Requests` |
| Empty state | `tray` | Title: `No booking requests`; Body: `New encrypted requests appear here after this app reads your inbox.` |
| Request row time status open | `checkmark.circle` | `Still open` |
| Request row time status conflict | `exclamationmark.triangle` | `Time no longer open` |
| Request row time status expired | `clock` | `Expired` |
| Approve action | `checkmark.circle` | `Approve request` |
| Decline action | `xmark.circle` | `Decline request` |
| Recheck action | `arrow.clockwise` | `Recheck availability` |
| Approval confirmation title | `calendar.badge.plus` | `Approve request?` |
| Approval confirmation body | none | `Calendar Busy Sync will add one busy event to the selected booking calendar.` |
| Decline confirmation title | `xmark.circle` | `Decline request?` |
| Decline confirmation body | none | `No calendar event will be created.` |

Appointment editor copy and icons:

| Element | Icon | Copy |
| --- | --- | --- |
| Screen title | `calendar.badge.plus` | `Appointment types` |
| Add action | `plus` | `Add appointment type` |
| Edit action | `pencil` | `Edit appointment type` |
| Delete action | `trash` | `Delete appointment type` |
| Preview action | `eye` | `Preview page` |
| Save action | `checkmark` | `Save appointment type` |
| Duplicate action | `plus.square.on.square` | `Duplicate appointment type` |
| Weekly hours editor | `calendar` | `Weekly hours` |
| Buffer editor | `arrow.left.and.right` | `Buffers` |
| Minimum notice editor | `clock.badge.exclamationmark` | `Minimum notice` |
| Location editor | `mappin.and.ellipse` | `Location` |
| Google Meet option | `video` | `Create Google Meet` |
| Share link action | `link` | `Copy share link` |
| Duplicate slug warning | `exclamationmark.triangle` | `Another appointment type already uses this link name.` |
| Missing duration warning | `exclamationmark.triangle` | `Add a duration before publishing.` |
| Invalid hours warning | `exclamationmark.triangle` | `Weekly hours must end after they start.` |
| Invalid buffer warning | `exclamationmark.triangle` | `Buffers must be zero or greater.` |
| Invalid minimum notice warning | `exclamationmark.triangle` | `Minimum notice must be zero or greater.` |
| Unsafe config warning | `exclamationmark.triangle` | `This field looks like a secret. Remove it before publishing.` |

Template customization copy and icons:

| Element | Icon | Copy |
| --- | --- | --- |
| Screen title | `pencil` | `Customize page` |
| Body | none | `Edit Markdown and CSS. Protocol files are protected.` |
| Open folder action | `folder` | `Open template folder` |
| Copy AI prompt action | `doc.on.doc` | `Copy AI prompt` |
| Validate action | `checkmark.circle` | `Validate template` |
| Protected files status | `lock` | `Protocol files unchanged` |
| Modified protocol warning | `exclamationmark.triangle` | `Protected files changed. Restore them before publishing.` |

Public booking page copy and web icon use:

| Public site element | Copy |
| --- | --- |
| Page title | `Request time with {publicName}` |
| Page subtitle | `Choose a time and send a private request.` |
| Privacy note | blank by default; hidden when empty |
| Appointment card metadata | `{duration} minutes` |
| Appointment card action | `Choose a time` |
| Slot picker heading | `Choose a time` |
| Time zone label | `Times shown in {timeZone}` |
| Visitor name label | `Name` |
| Visitor email label | `Email` |
| Topic question label | `What should we cover?` |
| Submit action for manual approval | `Send request` |
| Submit action for auto-confirm appointment types | `Book this time` |
| Success title for manual approval | `Request sent` |
| Success body for manual approval | `You will get a confirmation after this time is reviewed.` |
| Success title for auto-confirm | `Booked` |
| Success body for auto-confirm | `A calendar invite is on the way.` |
| Expired slot message | `This time is no longer available. Choose another time.` |
| Relay unavailable message | `Requests are not available right now. Try again later.` |
| Encryption unavailable message | `This browser cannot encrypt the request. Try another browser.` |

Public web icons, if used at all:

- `calendar` for appointment cards
- `clock` for duration and time
- `lock` for the privacy note
- `mail` for email
- `check` for success
- `alert-triangle` for recoverable errors
- `external-link` for opening docs or provider setup pages

Menu bar, toolbar, and command copy:

| Surface | Icon | Copy |
| --- | --- | --- |
| macOS menu bar item | `calendar.badge.plus` | `Booking` |
| Menu command | none | `Open booking setup...` |
| Menu command | none | `Publish booking page` |
| Menu command | none | `Copy booking link` |
| Menu command | none | `Check request inbox` |
| Toolbar item | `questionmark.circle` | `Help` |
| Toolbar item | `doc.text` | `Guide` |
| Toolbar item | `play.rectangle` | `Watch setup video` |

Accessibility labels:

- every icon-only native button must provide an accessibility label that exactly matches the visible equivalent in the tables above
- status icons include the status text in the accessible label, for example `Inbox is reachable`
- never include tokens, private keys, raw URLs with secret query strings, visitor email addresses, or decrypted visitor answers in accessibility labels unless they are already visible on screen for the user to act on
- public-site decorative icons use empty alt text or `aria-hidden="true"`; meaningful icons need visible adjacent text

Assumptions:

- GitHub Pages is the only static web host for the public booking page in the first implementation.
- The relay may be deployed to Cloudflare or Vercel, but it is not allowed to become a calendar backend.
- The native app can support app-managed GitHub publishing with a deploy key, app-managed Vercel setup with a user-provided token, and manual self-hosting where the user pastes already-created URLs and admin tokens.
- The first booking flow can default to manual approval; auto-confirm is configurable per appointment type once the existing local decrypt/recheck/write path is used.
- Google Meet creation requires the accepted-booking calendar to be a Google calendar with write access and Meet support; Apple / iCloud accepted-booking calendars can still use manually entered locations or generated `.ics` invites.
- Public booking pages may expose open slots, appointment type copy, theme assets, public keys, public relay URL, and opaque inbox/share IDs.
- Public booking pages must not expose calendar account emails, calendar IDs, provider event IDs, OAuth client secrets, relay admin tokens, private keys, or raw busy blocks.

## Plan of Work

Current follow-up slice:

1. Add a Vercel REST client under the Booking boundary that can upsert project env vars with `upsert=true`, create an inline-file deployment from `templates/booking-relay/vercel`, decode deployment URLs, and report phase-specific failures without logging tokens.
2. Extend secure storage and `AppModel` state so the Vercel account token and generated inbox admin token stay in Keychain, while non-secret Vercel project/team identifiers persist in local/shared settings.
3. Replace the Vercel Request Inbox UI so it asks for `Vercel token`, `Vercel project ID or name`, and optional team ID/slug, then exposes one `Deploy Vercel inbox` / `Redeploy Vercel inbox` action.
4. After a Vercel deploy, save the returned `https://...vercel.app` URL as the inbox URL, run the existing `/healthz` check, and show resulting evidence. If Vercel Blob/storage is missing, keep the failure in the inbox health/status path instead of asking for unexplained relay internals.
5. Update booking docs, Vercel template docs, this ExecPlan, and `.agents/DOCUMENTATION.md` to describe the project/token flow and the remaining Vercel Blob project prerequisite.
6. Validate with `python3 scripts/check_execplan.py`, `python3 scripts/knowledge/check_docs.py`, focused Booking/AppModel tests, and `git diff --check`.

1. Define the booking product and security contract.
2. Build a provider-neutral booking domain in the native app.
3. Add Markdown-backed appointment and theme configuration.
4. Generate a static GitHub Pages site from safe public artifacts.
5. Consolidate Booking setup and Booking settings into one platform-adaptive Booking workspace.
6. Add native multiple appointment-type creation and editing.
7. Add explicit page-file location, Finder, preview, and stale/local/live status controls.
8. Add a GitHub Pages setup and publishing workflow.
9. Build and verify the Cloudflare encrypted relay template.
10. Build, optionally deploy, and verify the Vercel encrypted relay template.
11. Add native app relay polling, request decryption, dedupe, expiry, auto-acceptance policy, Google Meet creation, and calendar-write approval.
12. Add onboarding instructions with text and video capture paths.
13. Add AI-coder customization guidance for the booking-site template.
14. Validate privacy, abuse controls, docs, and end-to-end booking behavior.

Milestone 0: HIG-informed setup UX design.

- Add a setup assistant design brief to `docs/product-specs/privacy-first-booking.md`.
- Define the four-step assistant:
  - Page: choose template, edit appointment basics, preview the public page, and generate keys.
  - Publish: choose GitHub Pages repo, generate or verify the deploy key, refresh page files, then publish.
  - Relay: choose Cloudflare recommended, Vercel, or custom compatible relay; open the deploy flow; paste or detect the relay URL; run health and CORS checks.
  - Test & Share: submit a synthetic encrypted request through the published page, import/decrypt it in the app, approve or decline it, then copy a share URL.
- Define platform presentations:
  - macOS: `Booking` settings toolbar pane for steady-state status; `BookingSetupAssistantWindow` for the guided setup; menu bar commands `Open Booking Setup...`, `Publish Booking Page`, `Copy Booking Link`, and `Check Booking Relay`.
  - iPhone: `NavigationStack` setup task with one primary action per screen, persistent save/resume, and no side-by-side dependency.
  - iPad: adaptive split view with setup steps on the leading side and active step details/preview on the trailing side.
- Define copy rules:
  - button labels use verbs tied to the user's goal, such as `Generate Page Files`, `Validate Token`, `Publish Page`, `Deploy Relay`, `Check Relay`, and `Send Test Request`
  - privacy explanations are one or two sentences beside the sensitive field, not long legal copy
  - advanced protocol details link to docs instead of crowding the first-run flow
- Define error and recovery states:
  - token rejected
  - repo not found
  - Pages not enabled
  - relay URL unreachable
  - CORS origin mismatch
  - encrypted test request not found
  - slot token expired
  - live calendar conflict during approval
- Define accessibility and automation requirements:
  - all setup steps and actions get stable accessibility identifiers
  - VoiceOver labels explain status without exposing secrets
  - setup can be completed with keyboard navigation on macOS and iPad
  - dynamic type and narrow iPhone layouts do not hide primary actions

Milestone 1: Product and threat model.

- Add `docs/product-specs/privacy-first-booking.md`.
- Extend `docs/SECURITY.md` with booking-specific trust boundaries:
  - static booking page boundary
  - relay boundary
  - GitHub publishing boundary
  - booking-request decryption boundary
  - calendar-write boundary
- Define non-goals:
  - no team scheduling in the first release
  - no server-side calendar integration in the relay
  - no plaintext booking details in relay storage
  - no visitor account requirement
  - no recurring appointment types in the first release unless already covered by simple duration rules
- Define the public artifact budget:
  - open slots only, not busy intervals
  - signed slot tokens with expiry
  - opaque share and inbox IDs
  - short publishing horizon
  - no sensitive source identifiers

Milestone 2: Booking domain and config.

- Add semantic Swift types under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/`:
  - `BookingProfileID`
  - `AppointmentTypeID`
  - `BookingShareID`
  - `BookingInboxID`
  - `BookingSlotID`
  - `BookingRequestID`
  - `BookingRelayURL`
  - `BookingPublicKey`
  - `BookingPrivateKeyReference`
  - `SignedBookingSlotToken`
  - `EncryptedBookingRequestEnvelope`
  - `BookingRequestLedgerEntry`
- Implement Markdown parsing for appointment types and theme/profile files.
- Reject invalid config explicitly with actionable diagnostics:
  - duplicate slugs
  - missing duration
  - unsupported question type
  - unsafe external script/reference
  - secret-looking values in Markdown frontmatter
  - calendar/provider IDs in public config
- Add fixtures under `Fixtures/booking/` that use synthetic names and no real account identifiers.

Milestone 3: Availability compilation and signed slots.

- Reuse normalized busy occupancy from selected calendars to calculate public open slots.
- Keep the availability compiler provider-neutral and deterministic.
- Generate signed slot tokens that encode only the minimum public appointment claim:
  - appointment type
  - start/end
  - all-day false for first release
  - generated-at
  - expires-at
  - nonce
  - public key or signing-key version
- Store signing/private-key material in Keychain or the platform-equivalent secure store.
- Add tests proving generated public artifacts do not contain provider event IDs, calendar IDs, access tokens, refresh tokens, account emails, or raw busy intervals.

Milestone 4: Static booking site template.

- Create `templates/booking-site/` as a small static web project.
- Prefer plain files over a heavy framework:
  - `index.html`
  - `assets/styles.css`
  - `assets/app.js`
  - `content/profile.md`
  - `content/appointment-types/*.md`
  - `public/availability/*.json`
  - `public/site-config.json`
  - `README.md`
  - `AI_CUSTOMIZATION.md`
- Use CSS variables and small named sections so users can ask an AI coding tool for targeted edits.
- Include `AI_CUSTOMIZATION.md` prompts:
  - "Change the visual style without changing encryption, request, or availability code."
  - "Add a new appointment type by editing only Markdown."
  - "Change copy and colors while preserving the public artifact schema."
  - "Explain what files are safe to edit and what files should not be touched."
- Ensure the template has no analytics, third-party fonts, third-party scripts, or runtime dependency on a build server.
- Include a static-page test that verifies request encryption happens before network submission.

Milestone 4A: Unified Booking workspace and appointment-type editor.

- Replace separate `Continue setup` and `Booking settings` sheets with one `Booking` workspace launched from the existing Booking section.
- Use a platform-adaptive structure:
  - macOS: a dedicated Booking window or large sheet with a sidebar for `Overview`, `Appointment types`, `Page files`, `Publish`, `Request inbox`, and `History`
  - iPhone: a `NavigationStack` with the same sections as list rows and a single primary action on each screen
  - iPad: sidebar navigation when width allows, falling back to the iPhone navigation flow
- Keep the Overview compact:
  - readiness status
  - selected appointment-type share link picker
  - active requests only
  - one primary next action
  - links to page-file, publish, inbox, and history sections
- Add a native appointment-type list and editor backed by the same Markdown files:
  - create
  - edit
  - duplicate
  - delete or deactivate
  - reorder for public page display
  - copy appointment-specific share link
- Appointment-type fields:
  - public name
  - link name / slug with uniqueness validation
  - public summary
  - duration
  - weekly hours with closed days and multiple windows per day
  - buffer before
  - buffer after
  - minimum notice / soonest bookable time from now
  - location mode: no location, custom text, phone call, Google Meet
  - automatic acceptance for this appointment type, default off
  - visitor questions, including name, email, topic, and guest emails
- Preserve the Markdown and AI-coder workflow:
  - the editor writes deterministic Markdown under `content/appointment-types/`
  - direct Markdown edits reload into the editor after validation
  - protocol/generated files remain protected from AI-coder customization
  - the app shows diagnostics instead of silently discarding unsupported Markdown
- Page-file controls live in the same workspace:
  - show the resolved local folder path
  - `Open in Finder`
  - `Change folder...`
  - `Generate page files`
  - `Preview local page`
  - show whether local files are newer than the live GitHub Pages site
- HIG rationale:
  - follow onboarding guidance by making setup task-based and resumable, not a manual to read
  - follow settings guidance by keeping infrequent credentials and provider details in one stable configuration area
  - follow disclosure-control guidance by putting GitHub deploy-key rotation, relay internals, and protocol fields behind clearly labeled advanced disclosure
  - follow data-entry guidance by deriving defaults from existing app state, validating inline, and asking only for values the app cannot infer

Milestone 5: GitHub Pages setup and publishing.

- Add native setup UI for:
  - GitHub repository owner/name
  - repository visibility / public Pages compatibility warning when needed
  - Pages URL
  - selected publish branch
  - deploy-key generation and public-key copy
  - deploy-key verification
  - page-file preflight
  - publish now
- Make publishing explain the local-to-live path:
  - local page files are generated in the `Page files` section
  - publishing commits those files to the configured repository branch root
  - GitHub Pages publishes that branch root to the public booking URL
  - `Verify live page` fetches the public config and compares a generated version/hash with local files
- Present this setup inside the Publish step of the assistant, not as a raw form in Advanced.
- Provide `Generate deploy key`, `Copy public key`, and `Verify deploy key` actions in the same screen.
- Show a non-secret preflight checklist:
  - repository reachable
  - deploy key installed with write access on the expected repository
  - Pages source configured
  - branch exists or can be created
  - repository root is empty or contains only current generated page files
  - page-file diff ready
  - last publish timestamp

Milestone 5A: Deploy-key-only GitHub publishing migration.

Assumptions:

- The booking page repository is dedicated to this app and GitHub Pages serves the repository root.
- The app does not need to configure GitHub Pages settings through the GitHub API. The user configures Pages once in GitHub, then the app only publishes files.
- The app cannot rely on `/usr/bin/git`, `/usr/bin/ssh`, or `/usr/bin/ssh-keygen` on macOS because App Store sandboxing can block Apple developer-tool shims such as `xcrun`. macOS app-managed publishing must use app-bundled helpers or an in-process Git implementation. iPhone and iPad keep generation and verification but do not perform app-managed GitHub publishing in this milestone.
- The app generates a new deploy-key pair per configured repository. A deploy key is not reused across repositories.
- The private key stays in secure storage. Temporary working trees and transient SSH wrapper files must live under app-owned Application Support or `TemporaryDirectory` paths and must not be checked in or logged.

Desired behavior:

- The Publish workspace no longer displays or stores `GitHub token`.
- The Publish workspace displays `Deploy key` setup state: not created, created locally, installed on GitHub with write access, verified, or needs rotation.
- The user enters only repository, branch, and public page URL for publishing.
- The app can generate a deploy key and show/copy the public key with explicit instructions to add it in GitHub repository settings with `Allow write access`.
- `Verify deploy key` runs a non-mutating SSH/Git check against `git@github.com:OWNER/REPO.git` using the stored private key and records success/failure in the Publication evidence card.
- `Publish page` regenerates page files, clones or fetches the target branch into a temporary working tree using that private key, checks that the repository root is empty or contains only generated booking files, replaces the root with the generated files, commits only when the tree changed, and pushes to the configured branch.
- The previous PAT/Contents API publisher is removed instead of left as an alternate primary path. No GitHub token remains in the UI, `BookingSecretStore`, docs, or app model except for a one-time migration cleanup that deletes old stored tokens if present.
- If a publish fails, the app reports the exact phase: key missing, key not installed, repository unreachable, root not empty, commit failed, or push failed.
- The docs explain deploy-key rotation: remove the old deploy key in GitHub, ask the app to generate a new key, add the new public key with write access, verify, then publish.

Implementation status as of 2026-06-05:

- `BookingGitHubPublisher` now clones over SSH with `GIT_SSH_COMMAND`, writes the private key only to a short-lived temporary file, blocks non-generated root content, commits changed generated files, and pushes `HEAD:<branch>`.
- `BookingSecretStore` now stores the deploy-key private key and deletes legacy GitHub token storage during initialization.
- `AppModel` now generates Ed25519 deploy keys on macOS, records public-key metadata, verifies keys with `git ls-remote`, and publishes with the stored private key.
- `ContentView` now exposes `Generate deploy key`, `Copy public key`, and `Verify deploy key` controls instead of a token field.
- `docs/self-hosting/booking-pages-github.md` now documents deploy-key setup and rotation.
- Live validation added a write-enabled deploy key to `moorage/booking-test`, verified `git ls-remote`, pushed a temporary smoke-test branch, and deleted that branch without changing `main`.

Implementation approach:

- Replace `BookingGitHubPublisher`'s REST Contents API implementation with a Git-over-SSH publisher:
  - introduce a `BookingGitHubDeployKey` value containing public-key text, created date, repository slug, and fingerprint
  - introduce a `BookingGitHubDeployKeyStore` or extend `BookingSecretStore` for the private key
  - introduce a small `BookingGitCommandRunner` protocol so tests can verify clone/fetch/commit/push command planning without running real Git
  - use a temporary `GIT_SSH_COMMAND` wrapper or `ssh -i <private-key-path> -o IdentitiesOnly=yes` environment for each Git invocation
  - run Git commands serially; never fire-and-forget publish work
  - keep the root-only generated-file preflight before commit and push
- Update `AppModel`:
  - remove `bookingGitHubTokenString`, token persistence, and `canPublishBookingPageToGitHub` token dependency
  - add deploy-key setup state, generate/rotate/verify actions, and phase-specific publish errors
  - make background availability publishing require a verified deploy key on macOS; on iOS, skip with an audit entry rather than pretending it can publish
- Update `ContentView`:
  - remove `SecureField(BookingCopy.Field.githubToken, ...)`
  - add `Generate deploy key`, `Copy public key`, `Verify deploy key`, and `Rotate deploy key` controls in Publish
  - show concise instructions: add the public key in GitHub repository settings as a deploy key with write access
  - keep `Publish page` disabled until repository, branch, page URL, generated page files, and a verified deploy key are present
- Update docs:
  - `docs/self-hosting/booking-pages-github.md`
  - `docs/product-specs/privacy-first-booking.md`
  - `.agents/DOCUMENTATION.md`
  - this ExecPlan
  - remove PAT setup copy from booking docs and UI copy registry
- Update tests:
  - `BookingTests` covers deploy-key generation metadata, token cleanup, root-only preflight, Git command planning, unchanged-tree skip, non-generated root block, and failure classification
  - AppModel-focused tests cover Publish disabled without a verified deploy key and enabled after successful verification
  - docs validation confirms no primary docs still ask for a GitHub token

Rollback:

- If Git-over-SSH publishing is unreliable locally, keep root-only manual publishing and verification intact while reverting only the app-managed deploy-key publisher.
- Do not reintroduce PAT as a parallel primary path without a fresh decision log entry; dual credential models would make setup less clear.
- Store the deploy-key private key only in secure storage.
- Prefer one generated deploy key per repository and never reuse deploy keys across repositories.
- The app does not automate Pages configuration in the deploy-key-only path; it guides the user to enable Pages manually.
- Verify publishing by:
  - using the generated private key with `git ls-remote` or an equivalent non-mutating Git command
  - confirming the configured branch is reachable
  - fetching `/public/site-config.json` and `/public/availability/slots.json` from the live URL
  - confirming the live artifacts contain no secret-looking values
- Add text instructions in `docs/self-hosting/booking-pages-github.md`:
  - create or choose a GitHub repo
  - enable GitHub Pages for the intended source
  - generate a deploy key in the app
  - add the public key to the repo with write access
  - verify the deploy key in the app
  - rotate or revoke the deploy key
  - recover if a publish fails
- Add an app-side "Copy instructions" action so users can hand the setup steps to Codex CLI or Claude Code CLI.
- Add a video script and capture command for:
  - creating the GitHub repo
  - adding the deploy key with write access
  - enabling Pages
  - publishing the first booking page
  - changing Markdown and republishing

Milestone 6: Cloudflare relay template.

- Create `templates/booking-relay/cloudflare/` with a Worker that implements only:
  - `POST /v1/inboxes/:inboxId/requests`
  - `GET /v1/inboxes/:inboxId/requests?cursor=...`
  - `DELETE /v1/inboxes/:inboxId/requests/:requestId`
  - `GET /healthz`
- Store encrypted envelopes in Workers KV or a Durable Object-backed inbox, selecting the simpler primitive after a proof-of-concept.
- Add abuse controls:
  - payload size cap, initially 16 KB
  - per-IP rate limit
  - per-inbox rate limit
  - max pending requests per inbox
  - short retention and expiry cleanup
  - optional Turnstile token verification
  - CORS allowlist for the configured GitHub Pages origin
  - no request-body logging
- Include `wrangler.toml`, `.dev.vars.example`, and README instructions.
- Add a Deploy to Cloudflare button for users who prefer one-click setup.
- In the native Relay step, Cloudflare is the recommended card and should include:
  - `Deploy Cloudflare Relay`
  - `Copy Allowed Origin`
  - `Paste Relay URL`
  - `Check Relay`
  - a compact privacy note that the relay receives ciphertext only
- Add text instructions in `docs/self-hosting/encrypted-relay-cloudflare.md`:
  - deploy from the template
  - set required secrets/env vars
  - configure allowed origin
  - copy the relay URL into the native app
  - rotate inbox/admin secrets
  - inspect/deploy from source for open-source users
- Add a video script and capture command for Cloudflare deployment.

Milestone 7: Vercel relay template.

- Create `templates/booking-relay/vercel/` with a minimal Function API matching the Cloudflare relay contract.
- Use Vercel environment variables for relay secrets and allowed origin.
- Use Vercel Blob or a similarly minimal Vercel-supported storage path for encrypted envelopes.
- Support app-managed Vercel setup where the user provides a Vercel token, project ID or name, and optional team ID or slug.
- App-managed Vercel setup needs:
  - Vercel account token stored in Keychain
  - optional Vercel team ID or slug
  - Vercel project ID or name
  - generated inbox ID, share ID, admin token, and retention settings
  - allowed website origin derived from the configured GitHub Pages URL
  - Vercel Blob storage attached to the project so `BLOB_READ_WRITE_TOKEN` is available
- App-managed Vercel setup performs:
  - target the Vercel project by ID or name
  - upsert encrypted environment variables
  - upload or redeploy the relay template
  - wait for the production deployment to become ready
  - write the resulting relay URL into Booking configuration
- Keep the same abuse controls where platform-supported:
  - payload size cap below Vercel Function limits
  - per-IP and per-inbox throttling through local storage/provider options or a documented limitation
  - max pending requests
  - short retention
  - CORS allowlist
  - no body logging
- Add a Vercel Deploy Button with required environment variable names, never values.
- In the native Relay step, Vercel is the alternate card and should include the same user-facing actions as Cloudflare, plus any documented limitation around rate limiting or storage cleanup.
- Verify Vercel setup by:
  - calling `GET /healthz`
  - posting a synthetic encrypted request from the configured Pages origin
  - confirming a wrong admin token is rejected
  - listing the inbox with the admin token
  - verifying the stored record contains no visitor plaintext
  - deleting the synthetic request
  - confirming CORS rejects an unapproved origin where local test tooling can assert it
- Add text instructions in `docs/self-hosting/encrypted-relay-vercel.md`:
  - deploy from the template
  - create any required storage
  - set environment variables
  - copy relay URL into the native app
  - rotate/redeploy
  - understand limitations compared with Cloudflare
- Add a video script and capture command for Vercel deployment.

Milestone 8: Native app relay and booking workflow.

- Add setup UI for choosing relay mode:
  - no relay yet
  - Cloudflare
  - Vercel
  - custom compatible relay URL
- Keep relay setup in the guided assistant first. The persistent settings pane should show current relay status, `Check Relay`, `Rotate Inbox`, and `Change Relay` rather than all setup internals.
- Status: the current slice has URL-based inbox setup, public health checks, manual admin-token import, request list UI, approve/decline actions, Apple Calendar writes, a global automatic-acceptance setting, per-appointment automatic-acceptance policy, Google Meet creation for Google Calendar approvals, and a unified Booking workspace. Relay-mode picking, token rotation, persisted request-ledger storage across launches, and full app-managed Vercel deployment remain future work.
- Add relay health check and diagnostics that reveal no secrets. Implemented for `/healthz`; admin-token request import is separate from health diagnostics.
- Add request polling/import:
  - cursor-based fetch
  - duplicate suppression
  - encrypted envelope download
  - local decryption
  - local request state for the app session
  - persisted local ledger storage across launches
  - delete-after-import when safe
  - status: cursor fetch, duplicate suppression, envelope download, decryption, session request state, and delete after approve/decline are implemented; persisted ledger storage is still future work.
- Add request validation:
  - schema version
  - request ID uniqueness
  - slot token signature
  - slot token expiry
  - appointment type still active
  - live calendar availability still open
  - visitor fields satisfy appointment questions
  - status: slot-token signature, expiry, envelope/plaintext consistency, and live selected-Apple-calendar availability recheck are implemented; appointment-type deactivation and appointment-question validation remain future work.
- Add approval UI:
  - pending requests list
  - approve
  - decline
  - automatic acceptance setting, default off, with per-appointment overrides
  - audit trail entries
  - status: pending list, approve, decline, audit trail entries, a global automatic-acceptance setting, and per-appointment automatic-acceptance policy are implemented.
- Add appointment-type scheduling policy:
  - weekly hours determine the day/time windows that can generate public slots
  - buffer before and buffer after expand conflicts before slot publication and before live approval checks
  - minimum notice hides slots sooner than the configured duration from the current time
  - duration controls slot length and is validated before publish
  - deactivated appointment types stop publishing new slots while existing pending requests remain resolvable until expiry
- Add calendar writing:
  - write confirmed booking into a user-selected booking calendar
  - mark event busy
  - include minimal necessary visitor details according to appointment policy
  - populate attendees for Google Calendar writes using the booker plus additional guests
  - when `Create Google Meet` is enabled, call Google Calendar with conference creation enabled and attach the resulting Meet details to the booking event
  - if the accepted-booking calendar is Apple / iCloud, keep EventKit writes and generated `.ics` invite files but disable automatic Google Meet creation unless the appointment type switches to a Google calendar target
  - let existing busy-sync reconciliation mirror the confirmed booking as opaque busy holds into other selected calendars
  - status: selected Apple / iCloud calendar writes, busy marking, iCloud `.ics` invite artifacts, Google attendee writes, Google Meet creation, and explicit per-appointment location policy are implemented.

Milestone 9: Onboarding text, video, and recovery.

- Add an in-app "Booking Page Setup" guided flow:
  - create keys
  - choose appointment profile
  - publish GitHub Pages site
  - deploy relay
  - connect relay URL
  - send test request
  - approve test booking
- Make the setup flow resumable and state-driven:
  - `notStarted`
  - `draftPageReady`
  - `githubValidated`
  - `sitePublished`
  - `relayConnected`
  - `testRequestReceived`
  - `readyToShare`
- Use context-specific help instead of a single long tutorial:
  - inline tip beside GitHub deploy-key setup
  - inline tip beside relay allowed origin
  - inline tip beside AI customization export
  - repair tip when the published site is stale
- Add docs:
  - `docs/self-hosting/booking-pages-github.md`
  - `docs/self-hosting/encrypted-relay-cloudflare.md`
  - `docs/self-hosting/encrypted-relay-vercel.md`
  - `docs/self-hosting/ai-template-customization.md`
- Add videos or reproducible video scripts:
  - GitHub Pages setup
  - Cloudflare relay deployment
  - Vercel relay deployment
  - customizing the template with an AI coder
  - revoking/rotating GitHub and relay secrets
- Store generated video artifacts under `artifacts/` only.
- Document that videos must not show real tokens, real calendar account emails, real event names, or real booking requests.

Milestone 10: Validation, docs, and release readiness.

- Add unit tests for:
  - Markdown parsing
  - config validation
  - public artifact redaction
  - slot-token signing and verification
  - request encryption/decryption
  - relay client request validation
  - booking ledger dedupe and expiry
- Add integration tests for:
  - static site artifact generation
  - Cloudflare relay contract using local Worker tooling or a local HTTP fake
  - Vercel relay contract using local Function tooling or a local HTTP fake
  - native app poll/decrypt/approve/write flow with synthetic calendar fixtures
- Add UI smoke coverage for:
  - setup screens
  - setup resume state
  - platform-adaptive setup presentation on macOS, iPhone, and iPad
  - page-file preflight
  - relay health check
  - pending booking request approval
- Update durable docs:
  - `README.md`
  - `ARCHITECTURE.md`
  - `docs/SECURITY.md`
  - `docs/harness.md`
  - `docs/debug-contracts.md`
  - `.agents/DOCUMENTATION.md`
- Run the full validation set listed below.

## Concrete Steps

1. Create `docs/product-specs/privacy-first-booking.md` with the booking model, privacy guarantees, explicit non-goals, public artifact schema, relay contract, and acceptance targets.
2. Update `docs/SECURITY.md` with the booking-specific trust boundaries and security review triggers.
3. Add booking domain files under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/`.
4. Add fixtures under `Fixtures/booking/` covering:
   - one appointment type
   - multiple appointment types
   - invalid Markdown
   - unsafe Markdown with secret-looking fields
   - stale slot tokens
   - duplicate booking requests
5. Add `templates/booking-site/` with a static site template, safe public JSON schema, Markdown content examples, and `AI_CUSTOMIZATION.md`.
6. Add `scripts/build-booking-site` to generate the booking site into `artifacts/booking-site/` from synthetic fixtures during validation.
7. Add setup-state models under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Onboarding/`, including `BookingSetupStep`, `BookingSetupState`, and `BookingSetupAction`.
8. Add centralized copy and icon registries:
   - `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingCopy.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingIconography.swift`
   - `templates/booking-site/content/default-copy.json`
   - `templates/booking-site/assets/icons/README.md`
9. Add tests that assert the setup views, menus, public-site fixture, and accessibility labels use the copy/iconography tables in this plan.
10. Add a `BookingAppointmentTypeStore` or equivalent app-facing boundary that can load, validate, create, update, duplicate, deactivate/delete, and serialize appointment Markdown deterministically.
11. Add appointment-type editor models and tests for slug uniqueness, weekly hours, buffers, minimum notice, per-type auto-acceptance, location mode, Google Meet gating, and question validation.
12. Add a unified `Booking` workspace that replaces separate setup/settings sheets and keeps Overview, Appointment types, Page files, Publish, Request inbox, and History in one navigation surface.
13. Add page-file folder state and actions:
   - resolve default sandbox-safe folder
   - change folder with a security-scoped bookmark where needed
   - open folder in Finder on macOS
   - generate files atomically
   - preview local page
   - compare local artifact version/hash to live site
14. Add platform-adaptive setup views:
   - `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Onboarding/BookingSetupAssistantView.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/App/Platform/macOS/Booking/BookingSetupAssistantWindow.swift`
   - `Calendar Busy Sync/Calendar Busy Sync/App/Platform/iOS/Booking/BookingSetupNavigationView.swift`
15. Replace PAT-based GitHub publishing with deploy-key-only publishing:
   - remove GitHub token UI and secure-storage paths from `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`, `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`, `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSecretStore.swift`, and `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingCopy.swift`
   - replace REST Contents upload logic in `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingGitHubPublisher.swift` with a Git-over-SSH publisher
   - add deploy-key generation, private-key storage, public-key display/copy, verification, rotation, and old-token cleanup
   - add a fake Git command runner so tests can cover clone/fetch/status/add/commit/push planning without network access
   - keep root-only empty-repository preflight before commit/push
16. Add GitHub publishing tests for deploy-key setup state, old-token cleanup, Git command planning, repository-root preflight, unchanged-tree skip, push failure diagnostics, and live artifact verification.
17. Add `docs/self-hosting/booking-pages-github.md` with both UI instructions and CLI-oriented guidance for users who prefer to configure their own repo manually.
18. Add `templates/booking-relay/cloudflare/` with Worker source, tests, Wrangler config, Deploy to Cloudflare button, and README.
19. Add `docs/self-hosting/encrypted-relay-cloudflare.md` with setup, rotation, recovery, and limitations.
20. Add `templates/booking-relay/vercel/` with Function source, tests, Vercel config, Deploy Button, and README.
21. Add Vercel deployer code under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/RelayDeployment/` or `Publishing/`, with a fake API client for project create/find, env upsert, deployment, and deployment-status polling.
22. Add `docs/self-hosting/encrypted-relay-vercel.md` with setup, rotation, recovery, and limitations.
23. Add relay client code under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Relay/`.
24. Add booking crypto code under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/Crypto/`, using platform crypto APIs instead of custom cryptographic primitives.
25. Add booking ledger and approval workflow under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/`.
26. Add Google Meet creation support in the Google calendar write boundary, including conference-data request creation, supported-conference detection, attendee updates, and failure diagnostics.
27. Add UI for booking setup, appointment editing, page files, GitHub publishing, relay connection, Vercel deployment, pending requests, approval, decline, and test request diagnostics.
28. Add `docs/self-hosting/ai-template-customization.md` with AI-agent-safe editing boundaries and prompts for Codex CLI and Claude Code CLI.
29. Add `scripts/capture-booking-onboarding-videos` and `docs/self-hosting/videos/README.md` with reproducible capture steps.
30. Update `README.md`, `ARCHITECTURE.md`, `docs/harness.md`, `docs/debug-contracts.md`, and `.agents/DOCUMENTATION.md`.
31. Run validation from `/Users/matthewmoore/Projects/calendar-busy-sync`:
   - `python3 scripts/check_execplan.py docs/exec-plans/active/2026-05-31-privacy-first-booking-pages-relay.md`
   - `python3 scripts/knowledge/check_docs.py`
   - `./scripts/test-unit`
   - `./scripts/test-integration`
   - `./scripts/test-ui-macos --smoke`
   - `./scripts/test-ui-ios --device both --smoke`
   - `./scripts/build-booking-site`
   - `./scripts/test-booking-site`
   - `./scripts/test-booking-relay-cloudflare`
   - `./scripts/test-booking-relay-vercel`
   - `xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-booking-deploy-key -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:'Calendar Busy SyncTests/BookingTests' test`
   - focused booking tests for appointment editor, page-file folder actions, deploy-key GitHub publisher, Vercel deployer, and Google Meet event creation

## Validation and Acceptance

Acceptance means:

- a user can configure a GitHub repository and a write-enabled deploy key without giving the app broad GitHub account access
- the app stores the deploy-key private key only in secure storage, never logs it, and removes old GitHub-token storage during migration
- the Booking UI has one coherent workspace for setup, settings, appointment types, page files, publishing, request inbox, and history
- the app shows the local page-file folder path, opens it in Finder on macOS, previews the local page, and explains whether local files have been published
- a user can publish generated page files from the app to the root of a dedicated empty GitHub Pages repository, then verify that the live page matches the latest generated artifacts
- GitHub publishing no longer supports PAT or Contents API upload as a primary or fallback path
- the app can generate a public GitHub Pages booking site from Markdown appointment and theme config
- a user can create, edit, duplicate, deactivate/delete, and reorder multiple appointment types without editing Markdown by hand
- appointment types persist as deterministic Markdown files that remain easy for Codex CLI, Claude Code CLI, or another AI coding tool to edit safely
- each appointment type supports duration, weekly hours, buffer before, buffer after, minimum notice / soonest bookable time, location mode, per-type auto-acceptance, and questions
- slot generation and live approval checks both honor weekly hours, buffers, duration, and minimum notice
- the generated site contains no provider credentials, access tokens, refresh tokens, private keys, calendar account emails, calendar IDs, provider event IDs, raw busy intervals, or plaintext booking requests
- the booking-site template can be customized through Markdown and CSS without changing the relay or crypto protocol
- the app surfaces the end-user editable template folder directly and generates page files from that folder, not from a developer-only source checkout path
- `AI_CUSTOMIZATION.md` clearly tells AI coding agents which files are safe to edit and which files must preserve protocol behavior
- the generated site exposes shareable URLs for appointment types and private/share links
- each appointment type can choose its own accepted-booking target calendar, and approval/decline writes use that appointment target without exposing target IDs in public artifacts
- visitors can submit booking requests without iCloud, GitHub, Google, Vercel, or Cloudflare authentication
- browser-side code encrypts request details before sending anything to the relay
- the Cloudflare relay template can be deployed by the user and stores only encrypted envelopes plus minimal metadata
- the Vercel relay template can be deployed by the user and stores only encrypted envelopes plus minimal metadata
- when the user chooses app-managed Vercel setup, the app asks for Vercel token, project ID or name, optional team ID or slug, and allowed origin; generates inbox secrets; stores secrets in Keychain; updates and deploys the project; and verifies the deployed relay contract
- both relay templates enforce payload size caps, CORS allowlists, retention, dedupe, and rate/abuse controls appropriate to the platform
- the native app can poll the relay, decrypt requests locally, dedupe them, validate slot tokens, recheck live calendar availability, and surface pending requests
- approving a request writes a calendar event only into the user-selected booking calendar
- when a Google calendar is selected and `Create Google Meet` is enabled for the appointment type, approving or auto-accepting creates a Google Calendar event with attendees, invite updates, and Meet conference details
- when an Apple / iCloud calendar is selected, approving still writes the EventKit booking event and generates invite-populated `.ics` artifacts, but the UI does not imply that it can create a Google Meet
- existing busy-sync logic mirrors confirmed bookings as opaque busy holds into other selected calendars without exposing appointment details to unrelated calendars
- declining a request performs only the configured decline-notice side effect before relay cleanup: Google creates a declined-owner attendee event with updates, while Apple / iCloud creates a decline `.ics` artifact; expiring a request performs no calendar write
- text instructions exist for GitHub Pages setup, Cloudflare relay deployment, Vercel relay deployment, AI customization, deploy-key rotation, relay-token rotation, and recovery
- video instructions or reproducible capture scripts exist for GitHub setup, Cloudflare deployment, Vercel deployment, and AI-based template customization
- the app provides a resumable four-step setup assistant with Page, Publish, Relay, and Test & Share steps
- setup and steady-state configuration do not duplicate fields across two unrelated surfaces; editing a value in the Booking workspace updates the setup snapshot and repair actions in the same place
- native booking UI uses the exact screen labels, button labels, status messages, error messages, menu commands, accessibility labels, and SF Symbol names from the `Copy and iconography specification` section unless this ExecPlan is updated first
- public booking pages use the exact user-facing labels and messages from the `Public booking page copy and web icon use` table unless the appointment Markdown explicitly overrides allowed marketing copy
- primary UI uses `request inbox` instead of `relay`; `relay` appears only in Advanced, docs, API-contract labels, and implementation filenames
- non-obvious native actions display both icon and text; icon-only controls are limited to conventional compact controls with tooltips and matching accessibility labels
- the public web template does not use SF Symbols and does not rely on icon-only controls
- copy and iconography live in central registries so tests can catch accidental drift
- on macOS, booking setup uses a stable settings pane plus a dedicated setup window for the multi-step task, not stacked sheets
- on iPhone, booking setup works as a single navigation task with Back/Cancel affordances and one primary action per screen
- on iPad, booking setup adapts to available width and can use a split view without requiring it
- advanced setup details are hidden behind disclosure controls and never block the recommended path
- context-specific tips appear beside GitHub deploy-key setup, relay origin, deploy URL, test request, and AI customization controls
- inline validation handles routine errors; alerts are reserved for destructive or blocking actions
- the setup flow can be completed using keyboard navigation and assistive technologies without exposing secrets in labels or logs
- all validation commands listed in `Concrete Steps` pass or have documented blockers in this plan

## Idempotence and Recovery

Publishing recovery:

- generated static artifacts are deterministic from the booking config, safe public availability artifacts, and template version
- republishing the same inputs should produce no meaningful diff
- if the repository root contains non-generated files, publishing stops before upload and tells the user which file to remove
- a failed GitHub publish should leave the previous Pages deployment intact
- local page-file generation writes to a temporary folder first, then atomically replaces the visible page-file folder so `Open in Finder` never reveals a half-written site
- the app keeps the last generated artifact hash and last verified live hash so it can show `Needs publish` without guessing
- the user can rotate the deploy key without changing appointment URLs: remove the old deploy key in GitHub, generate a new app key, add the new public key with write access, verify, then publish
- the user can switch repositories by publishing the same site to a new Pages URL and updating share links
- if Pages settings are not configured, the app gives clear manual Pages-source instructions instead of requesting GitHub API credentials

Relay recovery:

- relay requests are immutable encrypted envelopes keyed by `requestId`
- the native app ledger dedupes imported requests before calendar validation
- the app can safely poll the relay repeatedly with the same cursor
- delete-after-import can be retried without creating duplicate calendar events
- relay records expire automatically even when the native app is offline
- revoking or rotating an inbox ID disables old share URLs without affecting local calendar credentials
- if a relay provider fails, the user can deploy the other relay template and republish the static site with the new relay URL
- app-managed Vercel setup is idempotent: finding an existing project, upserting env vars, and redeploying the same template should converge on one working inbox rather than creating duplicate projects

Calendar-write recovery:

- the app must recheck live availability immediately before approving or auto-confirming a request
- a stale slot token or newly occupied slot must decline or require manual resolution instead of writing over the conflict
- provider write failures must surface in the booking ledger and audit trail
- confirmed booking events must be distinguishable from busy-sync mirror events so they are not mistaken for app-managed opaque mirror holds
- Google Meet creation failure must not silently create a meeting without a meeting link when the appointment type promises Google Meet; it should block approval or require explicit user confirmation to create without Meet
- changing an appointment type's Google Meet setting affects only future approvals and generated public metadata, not already-created calendar events
- disabling booking must stop polling and publishing while leaving existing calendar events untouched unless the user explicitly deletes them

Secret recovery:

- GitHub deploy keys, relay admin secrets, private booking keys, and provider credentials can be rotated independently
- old GitHub tokens saved by prior builds are deleted during migration and are never shown back to the user
- generated private deploy keys are written only to secure storage or a short-lived file used by one Git operation, then removed from disk
- public booking keys are versioned so old pending requests can either remain decryptable until expiry or be invalidated intentionally
- docs and video scripts must never record live secrets; any capture flow must use fake tokens or blurred/redacted fields

Setup recovery:

- setup state persists after each completed action so the user can quit and resume without repeating previous steps
- failed provider validations leave entered values editable and show a next repair action
- changing the relay or GitHub repo reopens only the affected setup step and preserves appointment config
- the completed setup view keeps repair actions available without reopening the entire first-run assistant

## Artifacts and Notes

Artifacts:

- generated booking sites live under `artifacts/booking-site/` during tests
- video captures live under `artifacts/self-hosting-videos/`
- relay local test output lives under `artifacts/booking-relay/`
- no generated artifacts should be committed unless a fixture is explicitly synthetic and stable

Instruction requirements:

- GitHub instructions must include text and video covering repo creation, Pages enablement, deploy-key public-key copy, adding the key with write access, app setup, first publish, republish, rotation, and revocation.
- Cloudflare instructions must include text and video covering one-click deploy, source audit, environment/secrets setup, allowed origin setup, relay URL copy, health check, and rotation.
- Vercel instructions must include text and video covering Deploy Button use, source audit, environment variable setup, storage setup, relay URL copy, health check, and rotation.
- AI customization instructions must include prompts for Codex CLI and Claude Code CLI and must explicitly warn agents not to edit encryption, relay submission, slot-token validation, or generated public artifact schemas unless the user is intentionally changing the protocol.
- In-app setup instructions must follow the HIG-informed rule that the next action is visible in context and the full docs are one click away, not the primary content of the flow.

Open questions:

- Should automatic acceptance become configurable per appointment type after the global setting has real-world soak time?
- Should the recommended Cloudflare relay use KV for simplicity or Durable Objects for stronger per-inbox consistency and cleanup behavior?
- Should Vercel support be first-class in the initial release or documented as a compatible template after the Cloudflare path is stable?
- Should appointment pages publish exact open slots or coarser "request windows" that reveal less about availability at the cost of more declines?
- Should iPhone/iPad ever support app-managed publishing through a bundled Git implementation, or should app-managed deploy-key publishing stay macOS-only while mobile can generate and verify?

Screencast plan:

- `scripts/capture-booking-onboarding-videos --topic github-pages`
- `scripts/capture-booking-onboarding-videos --topic cloudflare-relay`
- `scripts/capture-booking-onboarding-videos --topic vercel-relay`
- `scripts/capture-booking-onboarding-videos --topic ai-template-customization`
- `scripts/capture-booking-onboarding-videos --topic full-setup-assistant-macos`
- `scripts/capture-booking-onboarding-videos --topic full-setup-assistant-ios`

Each screencast must use synthetic accounts, a throwaway GitHub repository, throwaway relay projects, fake appointment content, and redacted tokens.

## Interfaces and Dependencies

Internal interfaces:

- booking availability depends on normalized busy state and selected participant calendars, but must not reuse mirror identity metadata as public booking identifiers
- booking confirmation writes depend on provider adapters through the same selected-calendar boundary used by busy mirroring
- booking setup UI depends on the existing SwiftUI settings shell and audit trail
- booking setup UI must adapt to macOS windowed settings, iPhone navigation, and iPad split presentation from shared setup-state models
- relay polling depends on a small HTTP client boundary with test doubles
- GitHub publishing depends on a separate publisher boundary with test doubles

External dependencies:

- GitHub Pages for static hosting
- GitHub deploy keys with write access for app-managed publishing
- app-bundled `booking-git`, `booking-ssh`, and `booking-ssh-keygen` helpers, or a later in-process Git implementation, for macOS deploy-key publishing
- Cloudflare Workers plus Workers storage/rate-limit/optional Turnstile for the recommended relay
- Vercel Functions plus Vercel-supported storage for the alternate relay
- platform secure storage for private keys and relay admin tokens
- platform crypto APIs for signing, verification, encryption, and decryption

Security dependencies:

- no custom cryptography
- no token or private-key logging
- no checked-in real `.env` values
- no visitor plaintext in relay logs
- no relay endpoint that accepts OAuth tokens
- no relay endpoint that can write calendars
- no generated Pages artifact that contains calendar provider identifiers

Validation dependencies:

- local relay contract tests must not require production Cloudflare or Vercel credentials
- any live relay smoke test must use throwaway relay projects and synthetic booking data
- docs validation must pass after adding self-hosting docs
- ExecPlan validation must pass whenever this plan changes

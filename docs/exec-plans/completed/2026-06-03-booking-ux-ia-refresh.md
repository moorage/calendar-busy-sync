# Booking UX and Information Architecture Refresh

## Purpose / Big Picture

The booking feature already supports appointment-type CRUD, local page generation, GitHub Pages publishing, encrypted Vercel or Cloudflare request inboxes, request import, and approval into a selected Apple calendar. The current user experience does not make that capability legible enough. Setup, appointment editing, page customization, publishing, verification, deployment, and requests are spread across overlapping surfaces, and the labels `Draft`, `Published`, `Verified`, `Live`, and `Disabled` do not yet map to durable user-visible states.

This ExecPlan implements the fixes recommended by `docs/ideas/backlog/booking-appointment-management-ux-ia-audit.md`. The end state is one native `Booking` workspace with explicit lifecycle states, reversible appointment-type pause/resume, first-class public-page customization, publish/deploy evidence, guided inbox setup, and public page states that work cleanly for both n=0 and n=5 appointment-type scenarios.

The existing privacy-first booking workstream in `docs/exec-plans/active/2026-05-31-privacy-first-booking-pages-relay.md` remains the implementation base. This plan owns the UX and information architecture refresh layered on top of that booking substrate.

## Progress

- [x] 2026-06-03T17:56Z Promoted the booking appointment management UX/IA audit into this active ExecPlan after reviewing the audit, the booking product spec, the existing booking ExecPlan, and the native/static booking implementation surfaces.
- [x] 2026-06-03T18:04Z Validated the new ExecPlan, ideation index, docs control plane, and whitespace after creating the plan and linking the promoted audit.
- [x] 2026-06-03T18:23Z Implemented the first booking UX/IA slice: one Booking workspace entry path, evidence-based generated/uploaded/live states, served fingerprint verification, appointment-type pause/resume, lifecycle badges, stable slug-edit guardrails, safer public-page customization guidance, n=0/n=1 public-page states, compact timezone disclosure, and standard quarter-hour slot rounding.
- [x] 2026-06-03T18:23Z Validated the implementation with booking template tests, relay tests, focused Booking XCTest coverage, macOS build/UI smoke, checkpoint capture, and installed-Chrome Playwright computer-use checks against the generated public page.
- [x] 2026-06-03T18:43Z Completed the native public-page customization and request-inbox IA: persisted profile/theme fields now feed generated artifacts, the Public Page section exposes safe customization and protected protocol files, publish evidence shows generation/upload/serve/fingerprint facts, guided Vercel setup shows required environment variables and evidence, and relay health reports non-secret allowed-origin/storage proof.
- [x] 2026-06-03T18:43Z Completed public visitor-state validation for n=0, n=1, n=5, n=20, no-slots, and local-preview states, including scroll containment and no horizontal overflow at browser/mobile widths.

## Surprises & Discoveries

- The native app currently has two competing booking management shapes: a compact four-step setup sheet (`Page`, `Publish`, `Inbox`, `Test`) and a broader workspace sheet (`Overview`, `Appointment type`, `Page files`, `Publish`, `Request inbox`, `History`). The workspace is closer to the right destination, but the setup sheet remains a parallel IA.
- A successful page verification currently proves reachability more than freshness. A public URL returning HTTP 2xx does not prove that the latest local appointment configuration, generated files, GitHub commit, and served `site-config.json` all match.
- The generated public page is strongest after a visitor selects a time. Before that, the n=1 appointment-type state leaves too much empty space, and the full IANA timezone select makes a secondary setting dominate the DOM and screen-reader order.
- The June 3 macOS checkpoint capture emitted state and performance output, but the rendered `window.png` contained placeholder blocks rather than useful Booking UI, so the audit's native UI findings are source-backed rather than screenshot-backed.
- Browser and Chrome plugin backends were unavailable in this session, so computer-use validation used local Playwright with the installed Google Chrome executable against `http://127.0.0.1:8097`.
- The first post-change browser pass exposed odd-minute demo availability (`11:14 AM`) caused by minimum notice using the current generated minute. The Swift compiler and static demo builder now round the first candidate slot up to the next 15-minute scheduling step.
- Relay health needed to expose non-secret setup evidence. Returning only `ok: true` made `Reachable` and `Ready for this page` visually indistinguishable, so `/healthz` now reports the configured `ALLOWED_ORIGIN` and storage backend without exposing admin tokens or request contents.
- Native preview was a stale-file risk if a user edited copy or theme and then opened the previous `index.html`. `Preview local page` now regenerates first and opens only if generation succeeds.
- iOS smoke validation built and booted the iPhone and iPad simulators, then stalled at `simctl launch` while dumping visible state for both devices. The processes were killed after no progress; this is recorded as a local simulator launch stall rather than a static-site or macOS-native validation failure.

## Decision Log

- Create a dedicated booking UX/IA ExecPlan rather than overloading `2026-05-31-privacy-first-booking-pages-relay.md`. The earlier plan remains the privacy, encryption, template, and relay implementation context; this plan owns the management workflow.
- Keep the native term `appointment type` for this plan. If product copy later changes to `event type`, treat that as a deliberate naming migration with tests for copy drift.
- Treat `Live` as a versioned state, not a reachability synonym. Verification must compare a served configuration fingerprint against the expected local/generated/uploaded fingerprint.
- Keep remote mutations limited to local, fixture, throwaway, or explicitly approved dev GitHub/Vercel resources. Do not use production credentials or mutate production repositories without explicit approval.
- Preserve the privacy contract: generated public artifacts must not contain calendar IDs, provider tokens, private keys, raw busy intervals, visitor plaintext, or selected calendar metadata.
- Ship the first implementation slice without app-managed Vercel project creation. This slice makes the native request-inbox status and publish evidence clearer, while full automated Vercel project mutation remains outside this UX/IA plan.
- Complete this plan with guided Vercel setup instead of native app-managed Vercel mutation. The app now makes the required deployment inputs, environment variables, URL/admin-token capture, allowed-origin comparison, and test-request proof legible; it does not shell out to Vercel CLI or mutate Vercel projects because that would require broader secret handling and deployment ownership than this UX/IA refresh needs.
- Mark the plan complete with iOS smoke risk recorded. The acceptance surface was validated through macOS build, macOS UI smoke, focused Booking XCTest coverage, static booking/relay tests, local Playwright computer-use checks, and generated onboarding artifacts; the only incomplete command is the documented iOS simulator launch stall after successful build/boot.

## Outcomes & Retrospective

The booking flow now has one native management workspace with explicit lifecycle evidence instead of a split setup/steady-state IA. Users can create and pause/resume appointment types, customize public name/title/subtitle/timezone/theme in the app, generate and preview fresh local page files, see safe customization and protected protocol files, publish with upload/serve/fingerprint evidence, configure an existing inbox or follow guided Vercel setup, verify allowed-origin readiness, import requests, and approve or decline them.

The confusing `draft` / `published` / `verified` / `live` boundary is now version-based. `Live` requires a served public configuration fingerprint match; local edits to appointment types, profile copy, theme, or page settings move the page back to a pending/generated state until regeneration, upload, and verification catch up. The public page handles paused/no-active, one-type, five-type, twenty-type, no-slot, and local-preview states without hiding the request form incorrectly or letting appointment cards/timezone controls dominate the page.

Deferred scope is limited to app-managed remote deployment. Guided Vercel deployment is complete for the UX and information architecture target, but automatic Vercel project creation, environment mutation, and production deployment from inside the native app remain intentionally out of scope for this completed plan.

## Context and Orientation

Primary files and surfaces:

- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift` contains the current native shell, booking setup sheet, booking workspace sheet, appointment-type editor, page-files workspace, publish workspace, request-inbox workspace, and history surfaces.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift` persists booking settings and implements appointment CRUD, page generation, GitHub publishing, public page verification, inbox health checks, test-request sending, request import, and approve/decline actions.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSetupState.swift` computes the current setup progress and recommended next step.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingConfiguration.swift`, `BookingDraftFactory.swift`, `BookingStaticSiteGenerator.swift`, `BookingStaticSiteWriter.swift`, `BookingGitHubPublisher.swift`, and `BookingRequestModels.swift` define the booking data model, generated site payloads, publishing path, and request wire contract.
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingCopy.swift` and `BookingIconography.swift` centralize native copy and SF Symbol choices. Extend these registries instead of scattering new labels or icons.
- `Calendar Busy Sync/Calendar Busy Sync/Harness/AccessibilityIDs.swift` carries UI-test identifiers for native booking surfaces.
- `Calendar Busy Sync/Calendar Busy SyncTests/BookingTests.swift` is the focused test home for booking domain, page generation, request import, and state-machine coverage.
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift` is the UI smoke surface for native booking workflows.
- `templates/booking-site/index.html`, `templates/booking-site/assets/app.js`, `templates/booking-site/assets/styles.css`, `templates/booking-site/content/profile.md`, `templates/booking-site/content/appointment-types/*.md`, and `templates/booking-site/content/default-copy.json` define the public page visitors see and the safe customization files users need to discover from the native app.
- `scripts/build-booking-site`, `scripts/test-booking-site`, `scripts/test-booking-relay-cloudflare`, `scripts/test-booking-relay-vercel`, and `scripts/capture-booking-onboarding-videos` are the current booking validation and artifact scripts.
- `docs/product-specs/privacy-first-booking.md`, `docs/harness.md`, `docs/debug-contracts.md`, and self-hosting docs must stay aligned with any state model, setup, or deployment workflow changes.

Assumptions:

- Appointment request import and approval behavior remains functionally intact while the management UI changes.
- Existing generated page and relay wire contracts stay backward compatible unless a migration is explicitly documented.
- Stable public links matter. Appointment-type identity should not depend on mutable display copy, and changing a slug should not silently sever history or existing requests.
- macOS and iPad can carry a denser management workspace than iPhone. iPhone should expose the same top-level sections through a navigation stack.

## Plan of Work

1. Define a single booking lifecycle model.
   - Add explicit state types for page publication, request inbox readiness, and appointment-type lifecycle. The user-visible states are `Not set up`, `Local draft`, `Generated locally`, `Uploaded`, `Live`, `Live, changes pending`, `Verification failed`, and `Disabled` for the page; `Not connected`, `Configured`, `Reachable`, `Allowed-origin mismatch`, `Ready`, `Import failed`, and `Disabled` for the inbox; and `Draft`, `Live`, `Changed locally`, `Paused`, `No slots`, and `Broken` for appointment types.
   - Add a publication/version concept that records local configuration fingerprint, generated artifact fingerprint, GitHub commit SHA, served public configuration fingerprint, generated/uploaded/verified timestamps, and verification failure reason.
   - Make verification fetch public `site-config.json` and compare the expected fingerprint. Keep HTTP reachability as one input, not the final proof.

2. Collapse setup into one `Booking` workspace.
   - Replace the parallel setup sheet with an `Overview` readiness checklist inside the Booking workspace.
   - Use the same sections everywhere: `Overview`, `Appointment Types`, `Public Page`, `Publish`, `Request Inbox`, and `Requests`.
   - On macOS and iPad, use a `NavigationSplitView` or equivalent workbench: section navigation, content list/checklist, and selected detail. On iPhone, use a `NavigationStack` with the same sections as rows.
   - Show each section as a status/action row with an SF Symbol, current state, timestamp or evidence, and one primary next action.

3. Improve appointment-type management.
   - Add reversible `Pause` and `Resume` actions that hide/show an appointment type on the public page while preserving history and marking the page as changed until republished.
   - Keep `Delete` destructive and confirmed, with stronger warning when historical requests exist.
   - Prefer stable appointment-type IDs separate from mutable slugs where feasible; if that migration is too large, add explicit guardrails and tests around slug changes.
   - Add card badges for `Draft`, `Live`, `Changed`, `Paused`, `No slots`, and `Broken`.
   - Design and test n=0, n=1, n=5, and n=20 states so empty, normal, and large appointment lists stay understandable.

4. Make public-page customization native.
   - Add a `Public Page` section with common profile/copy fields, theme controls, local preview, safe-file shortcuts, page regeneration, and a page safety check.
   - Surface the safe customization files currently documented under `templates/booking-site/content/` and `templates/booking-site/assets/styles.css`.
   - Add a protected-files disclosure for protocol-sensitive files that should not be edited casually because they carry signing, encryption, or request-flow behavior.
   - Ensure generated public artifacts continue to pass the existing secret and privacy scans.

5. Make publishing and Vercel deployment evidence-based.
   - In `Publish`, separate local generation, GitHub upload, GitHub Pages serving, and live fingerprint verification. Show repository, branch/folder, last upload timestamp, commit SHA, expected fingerprint, served fingerprint, last verification time, and failure reason.
   - Validate GitHub token/repo/branch inputs before upload where possible, and make GitHub Pages delay explicit after upload.
   - In `Request Inbox`, support `Use existing inbox` and `Guided Vercel deploy`. The guided path should expose required environment variables, production/preview context, deploy URL capture, `/healthz` check, `ALLOWED_ORIGIN` comparison, and test-request evidence.
   - If app-managed Vercel deployment is implemented using `VERCEL_ACCOUNT_TOKEN` or a user-entered token, create/update the project, set environment variables, deploy, capture the production URL, verify health, and record status without logging secrets.

6. Polish the public booking page states.
   - For n=1 appointment type, reduce or remove the persistent side rail and make the chosen type feel like page context instead of a selectable catalog.
   - For n=5 appointment types, keep cards compact and scannable without crowding the scheduling pane.
   - Replace the giant timezone select with a compact, searchable, or deferred control so timezone remains available without dominating the page.
   - Add explicit no-slots and paused/no-active-types states.
   - Keep local preview visually distinct from live public pages.
   - Remove or adjust demo availability that creates odd fixture times such as `2:01 AM`.

7. Update tests, docs, and artifacts.
   - Add unit tests for the lifecycle state model, publication fingerprint comparisons, pause/resume semantics, slug/ID behavior, and state-to-copy/icon mappings.
   - Extend static template tests for n=1, n=5, no slots, local preview, timezone control, and safety scanning.
   - Add native UI smoke coverage for entering the Booking workspace, following the overview checklist, editing an appointment type, pausing/resuming, publishing, verifying, configuring an inbox, and importing a test request.
   - Update `docs/product-specs/privacy-first-booking.md`, `docs/harness.md`, `docs/debug-contracts.md`, self-hosting/customization docs, `.agents/DOCUMENTATION.md`, and the booking onboarding video scripts.

## Concrete Steps

1. Inventory the current booking UI and state flow in `ContentView.swift`, `AppModel.swift`, `BookingSetupState.swift`, and `BookingConfiguration.swift`. Record exact current states and actions before changing code.
2. Add booking lifecycle value types and pure derivation helpers in the booking shared module. Keep side effects at `AppModel` boundaries.
3. Extend generated `site-config.json` with a public, non-secret configuration fingerprint and any non-sensitive version metadata needed for freshness verification.
4. Update local generation, GitHub upload, public verification, and inbox checks to record version evidence. Ensure old configs without fingerprints produce a clear compatibility state rather than a false `Live`.
5. Refactor native Booking IA into one workspace. Retire the setup sheet as a separate journey and reuse its useful step logic as the `Overview` checklist.
6. Add appointment-type pause/resume, card badges, delete confirmation improvements, and stable identity guardrails.
7. Build the `Public Page` customization surface, including safe-file shortcuts, theme/copy controls, local preview, protected-file disclosure, and safety-check action.
8. Rework `Publish` and `Request Inbox` screens around evidence rows, next actions, Vercel guidance, health checks, and test-request proof.
9. Update the static public page for n=1, n=5, no-slots, paused/no-active-types, timezone control, and local-preview states.
10. Add or update focused tests, UI accessibility IDs, docs, onboarding video scripts, and generated artifacts.
11. Run the validation commands in this plan, update `Progress`, `Surprises & Discoveries`, `Decision Log`, `.agents/DOCUMENTATION.md`, and move this plan to completed only after acceptance evidence is recorded.

## Validation and Acceptance

Acceptance criteria:

- From no booking configuration, a user can open `Booking`, create the first appointment type, understand the readiness checklist, generate local files, preview the public page, publish to GitHub Pages, verify the served version, configure an inbox, send a test request, import it, and approve or decline it.
- Editing an appointment type, profile copy, theme, or page setting after a verified live publish changes the state to `Live, changes pending` until the new version is generated, uploaded, served, and verified.
- A paused appointment type disappears from the public page after publish, remains visible in native management/history, and can be resumed without recreating it.
- Appointment-type cards and public page states remain clear at n=0, n=1, n=5, and n=20.
- Vercel setup shows whether an inbox URL is configured, reachable, allowed for the current booking-page origin, ready for imports, or failing.
- Every `Live` claim shows the public URL, generation/upload/verification evidence, and matching expected/served fingerprints.
- Public artifacts and logs do not expose provider credentials, private keys, calendar IDs, raw busy intervals, visitor plaintext, admin tokens, or secret-looking values.

Validation commands:

- `python3 scripts/check_execplan.py docs/exec-plans/completed/2026-06-03-booking-ux-ia-refresh.md`
- `python3 scripts/knowledge/check_docs.py`
- `./scripts/test-booking-site`
- `./scripts/test-booking-relay-cloudflare`
- `./scripts/test-booking-relay-vercel`
- `xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-booking-ux -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -only-testing:'Calendar Busy SyncTests/BookingTests' test`
- `./scripts/build --platform macos`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `./scripts/capture-booking-onboarding-videos`
- `git diff --check`

If hosted XCTest or UI smoke runners hit the documented local stall pattern, record the command, the point of failure, and the direct fallback evidence used instead. Do not mark native acceptance complete from static-site tests alone.

## Idempotence and Recovery

All publication actions must be repeatable. Re-running generation with the same appointment/page configuration should produce the same public fingerprint, and re-running verification should not mark stale remote content as live. Re-running upload should either produce a new commit with changed content or clearly report no content changes.

Pause/resume must be reversible and must not delete request history. Delete remains a confirmed destructive action. Remote GitHub/Vercel operations should use dev or throwaway resources unless the user explicitly approves production resources for a smoke test.

Rollback is straightforward if each milestone stays scoped: keep the older setup sheet code until the new workspace passes native smoke coverage, keep wire-contract changes backward compatible where possible, and regenerate public artifacts from the previous template if the public page changes regress. If a fingerprint field is added to public config, old served pages should verify as `reachable, version unknown` or `verification failed`, not as `Live`.

## Artifacts and Notes

- Audit source: `docs/ideas/backlog/booking-appointment-management-ux-ia-audit.md`.
- Existing implementation plan: `docs/exec-plans/active/2026-05-31-privacy-first-booking-pages-relay.md`.
- Planning validation evidence from 2026-06-03: `python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-03-booking-ux-ia-refresh.md`, `python3 scripts/knowledge/check_docs.py`, and `git diff --check` passed.
- Implementation validation evidence from 2026-06-03:
  - `xcrun swiftc -typecheck 'Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/'*.swift` passed.
  - `./scripts/test-booking-site`, `./scripts/test-booking-relay-cloudflare`, and `./scripts/test-booking-relay-vercel` passed.
  - `xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-booking-ux -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -only-testing:'Calendar Busy SyncTests/BookingTests' test` passed, including fingerprint, paused appointment type, decoding default, and quarter-hour slot tests.
  - `./scripts/build --platform macos`, `./scripts/test-ui-macos --smoke`, and `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint booking-ux-refresh-shell` passed.
  - Playwright with installed Chrome against `artifacts/booking-site-test` confirmed one appointment type auto-selects with the side rail hidden, no active types show `Booking is paused`, the timezone control stays inside a disclosure with 9 options, the generated config has a 64-character fingerprint, the details step shows `Selected Thursday, June 4 at 11:30 AM.`, and mobile had no horizontal overflow at 390 px.
- Completion validation evidence from 2026-06-03:
  - `xcrun swiftc -typecheck 'Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/'*.swift` passed after the native public-page and request-inbox additions.
  - `./scripts/test-booking-site` passed with assertions for local-preview detection, preview banner styling, n=20 appointment-list scroll containment, compact timezone disclosure, n=1/no-active states, public fingerprinting, and privacy scanning.
  - `./scripts/test-booking-relay-cloudflare && ./scripts/test-booking-relay-vercel` passed with health-response checks for non-secret `allowedOrigin` and `storage` evidence.
  - `./scripts/build --platform macos` passed.
  - `xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-booking-ux -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -only-testing:'Calendar Busy SyncTests/BookingTests' test` passed, including custom profile/theme/share-ID generation and relay health decoding.
  - `./scripts/test-ui-macos --smoke` passed.
  - `./scripts/capture-booking-onboarding-videos` passed and wrote scripts under `artifacts/booking-onboarding-videos`.
  - `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint booking-ux-completion-shell` passed and captured `artifacts/checkpoints/booking-ux-completion-shell`.
  - Playwright with installed Chrome against `http://127.0.0.1:8097` passed for n=1, n=5, n=20, n=0/no-active, no-slots, n=5-selected, and n=20-selected states. Screenshots were written to `artifacts/booking-site-test/completion-n1.png`, `completion-n5.png`, `completion-n20.png`, `completion-n0.png`, `completion-no-slots.png`, `completion-n5-selected.png`, and `completion-n20-selected.png`.
  - `./scripts/test-ui-ios --device both --smoke` and `./scripts/test-ui-ios --device ipad --smoke` both built and booted simulators, then stalled at `simctl launch ... --dump-visible-state`; child processes were killed after no output. Treat this as residual local iOS simulator launch risk.
- Public page audit artifacts from June 3 live under `artifacts/booking-ux-audit-site` and related checkpoint folders when present locally; do not check generated artifacts into the repo.
- Current implementation screenshots live locally under `artifacts/booking-site-test/booking-ux-desktop.png`, `artifacts/booking-site-test/booking-ux-mobile.png`, and `artifacts/booking-site-test/booking-ux-paused.png`.
- Future validation should capture desktop and mobile screenshots of the native Booking workspace and public page n=1/n=5/no-slots states, plus any live smoke URLs and commit SHAs used for dev-only GitHub/Vercel verification.
- Logs, screenshots, and result bundles must redact or omit `.env` secrets, GitHub tokens, Vercel tokens, inbox admin tokens, private keys, visitor plaintext, and provider credentials.

## Interfaces and Dependencies

Native dependencies:

- SwiftUI workspace components in `ContentView.swift`.
- Booking state and persistence in `AppModel.swift`.
- Booking setup/state derivation in `BookingSetupState.swift`.
- Booking data contracts in `BookingConfiguration.swift` and `BookingRequestModels.swift`.
- Static-site generation and publishing in `BookingStaticSiteGenerator.swift`, `BookingStaticSiteWriter.swift`, and `BookingGitHubPublisher.swift`.
- Central copy and icon registries in `BookingCopy.swift` and `BookingIconography.swift`.
- Accessibility identifiers in `AccessibilityIDs.swift`.

Static site and relay dependencies:

- `templates/booking-site/` for visitor-facing scheduling, safe customization files, and generated public assets.
- Cloudflare and Vercel relay templates and tests for `/healthz`, allowed-origin behavior, encrypted request storage, admin-token import, and deletion.
- GitHub Pages serving behavior, including public repository visibility, branch/folder source selection, static entry-file requirements, and deployment delay.
- Vercel production/preview environment behavior, Deploy Button or CLI/app-managed deployment, and required environment variables.

Privacy and security interfaces:

- Public `site-config.json` may expose non-secret version metadata and fingerprints only.
- Generated artifacts must continue to pass the booking site's privacy scanner.
- Remote deployment helpers must never log tokens or serialize secrets into docs, public files, screenshots, or result bundles.

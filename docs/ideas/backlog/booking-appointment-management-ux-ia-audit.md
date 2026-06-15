# Booking Appointment Management UX / IA Audit

## Snapshot

- Status: `promoted`
- Priority lane: `now`
- Impact: `high`
- Confidence: `high`
- Effort: `high`
- Last reviewed: `2026-06-03`
- Completed ExecPlan: `docs/exec-plans/completed/2026-06-03-booking-ux-ia-refresh.md`

## Why this matters

The booking workstream is now powerful enough to expose product-level confusion. A user can create appointment types, generate public page files, publish to GitHub Pages, connect a Vercel or Cloudflare encrypted inbox, test requests, import requests, and accept or decline bookings. The current UX does not make those lifecycle boundaries legible enough.

The biggest issue is that setup, CRUD, publishing, verification, deployment, and request operations are spread across overlapping surfaces with state labels that do not map cleanly to user intent:

- `Draft` is implied by locally generated page files but not shown as a first-class state.
- `Published` currently means the page URL returned HTTP 2xx, not necessarily that the latest local appointment changes are live.
- `Verified` is an action label, not a stable state with timestamp, origin, commit, or config fingerprint.
- `Live` is user language, but the app mostly says `published` or `ready`.
- `Disabled` appointment types do not exist; users can only delete an appointment type or leave it visible.
- `Vercel` appears as fields and explanatory copy, not as an actual deploy/manage/verify flow.
- `Customize HTML page` lives in docs and template files, not in the native task flow where users look for it.

The result is that a capable feature feels less trustworthy than it is.

## Current evidence

This audit used four evidence streams:

- Source inspection of `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`, `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`, `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSetupState.swift`, `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingCopy.swift`, and `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingIconography.swift`.
- Local static-site build with `./scripts/build-booking-site --output artifacts/booking-ux-audit-site`.
- Browser walkthrough of the generated public page at `http://127.0.0.1:8097/` using Chrome and Playwright, including desktop and mobile viewports.
- macOS harness capture with `./scripts/capture-checkpoint --scenario basic-cross-busy.json --platform-target macos --checkpoint booking-ux-audit-shell`. The checkpoint state emitted correctly, but `window.png` rendered placeholder blocks instead of a useful live Booking UI screenshot, so native UI findings are source-backed rather than screenshot-backed.

External references checked:

- Apple Human Interface Guidelines: Onboarding, Settings, Sheets, Disclosure controls, and Split views.
- GitHub Pages docs: repository/source setup, public nature of Pages, entry-file rules, static-file publishing, and possible publish delay.
- Vercel docs: Deploy Button, environment variables, deployment methods, Git-triggered deployments, CLI deployments, and production/preview/local environments.

### Current native IA

There are two overlapping booking management surfaces:

- Compact setup sheet: `Page`, `Publish`, `Inbox`, `Test`.
- Booking workspace sheet: `Overview`, `Appointment type`, `Page files`, `Publish`, `Request inbox`, `History`.

The workspace is closer to the right end state, but the setup sheet remains a parallel IA. It has fewer controls than the workspace, uses a different step model, and can leave users unsure whether they should continue setup or open Booking settings.

### Current appointment-type editor

The current editor has several good ingredients:

- Appointment cards are compact and selectable.
- `Add appointment type`, duplicate, and delete exist.
- Detail editing is one selected appointment type at a time.
- Duration/location/availability are behind disclosure groups.
- Weekly hours are visual day rows instead of raw Markdown.
- Copy/open share-link actions are available per type when a page URL exists.

The missing pieces are lifecycle and publish context:

- Cards do not show whether that appointment type is live, changed locally, unpublished, disabled, broken, or missing slots.
- Edits auto-save locally and mark the page as needing publish, but the editor does not keep a persistent per-type "changes are not live" warning next to the edited type.
- Slug edits mutate the appointment type ID, which risks making link identity and historical request identity feel unstable.
- There is no `Disable` or `Pause` action, so delete is overloaded as the only way to remove a type from the public page.

### Current publish and deploy flow

The app has fields for GitHub repository, branch, token, inferred Pages URL, and page URL. It can publish generated files through `BookingGitHubPublisher.publishDirectory`. After upload, it sets page status to `needsPublish` with "Verify the live page after GitHub Pages finishes deploying."

That behavior is correct technically, but confusing semantically. Upload is not publish completion. Page verification is not latest-version verification. The app needs a visible chain:

1. Local files generated.
2. Files uploaded to repository commit `<sha>`.
3. GitHub Pages deploy observed or user asked to wait.
4. Live site served expected booking config fingerprint.
5. Inbox health check passed for that live origin.
6. Test request encrypted, relayed, imported, decrypted, and optionally approved.

Vercel is weaker. The workspace has `Vercel scope` and `Vercel project` fields plus prose telling the user to set `ALLOWED_ORIGIN`, but it does not expose a guided deploy button, project creation, environment-variable checklist, redeploy action, deployment URL capture, or deployment status. This explains why a user cannot figure out how to push changes and deploy the site.

### Current public page

The generated public page has a clear details step once a time is selected. The selected time summary is prominent, the form is linear, guest emails are addable/removable, and submission copy is understandable.

Problems:

- The n=1 public page first viewport shows one appointment card and large empty space before the visitor clicks.
- On desktop, the appointment list remains a side rail even when there is only one type.
- On mobile, the page is usable but the selected appointment card and scheduler stack can feel repetitive.
- The timezone control is a full IANA timezone select with hundreds of options in DOM and screen-reader order. It is a secondary setting that becomes one of the largest structures in the page.
- The demo availability produced a `2:01 AM` slot. Even if this is only fixture/demo data, it makes the product feel less intentional.

## Findings

### P0: Replace parallel setup surfaces with one Booking workspace

Do not keep both a four-step setup sheet and a six-section workspace as peers. A user should have one place called `Booking` that owns setup, appointment types, page customization, publishing, inbox deployment, requests, and history.

Recommended structure:

- `Overview`: readiness checklist, current live URL, current inbox, latest publish, latest verification, pending requests.
- `Event Types`: create, edit, duplicate, disable, delete, copy links, preview public page.
- `Public Page`: profile copy, theme/style entry point, safe customization files, local preview, local files.
- `Publish`: GitHub repository, branch, token validation, upload, deployment evidence, live verification.
- `Request Inbox`: provider choice, Vercel/Cloudflare setup, environment variables, health check, admin token, import.
- `Requests`: active requests first, history second.

The existing setup sheet can become the empty-state checklist inside `Overview`, not a separate modal journey.

### P0: Introduce a real publish state model

Use a single state machine that separates local config, repository upload, remote deployment, live verification, and inbox readiness.

Recommended page states:

- `Not set up`: no local page configuration exists.
- `Local draft`: appointment/page config exists locally but has never been generated or uploaded.
- `Generated locally`: page files exist on disk; no upload has happened for this version.
- `Uploaded`: files were committed to GitHub, but live Pages has not served the expected version yet.
- `Live`: public URL is reachable and serves the expected config fingerprint.
- `Live, changes pending`: the public URL is live, but local appointment/page settings changed after the verified version.
- `Verification failed`: URL or expected version check failed.
- `Disabled`: booking page is intentionally not accepting new requests.

Recommended inbox states:

- `Not connected`: no inbox URL.
- `Configured`: app-managed inbox settings saved, no health check yet.
- `Reachable`: health endpoint works.
- `Allowed-origin mismatch`: inbox works but rejects the current booking page origin.
- `Ready`: inbox health works and test request path succeeds.
- `Import failed`: admin-token import failed.
- `Disabled`: inbox intentionally paused.

Recommended appointment-type states:

- `Draft`: exists locally but has not been published.
- `Live`: present on live page with matching fingerprint.
- `Changed locally`: differs from live version.
- `Paused`: hidden from public page, existing history preserved.
- `No slots`: live but no current availability.
- `Broken`: validation failed or link slug conflict.

Implementation detail: add a generated configuration fingerprint to the public `site-config.json`, publish result, and local app state. Verification should fetch the public config and compare the fingerprint, not only check HTTP 2xx.

### P0: Make publish/deploy evidence visible

Every `live` claim should show:

- public URL
- last local generation time
- last GitHub repository upload time
- commit SHA or content version
- last live verification time
- expected config fingerprint
- served config fingerprint
- last inbox health check time
- last test request result

Do not use `Published` without showing whether it means uploaded to GitHub or served by GitHub Pages.

### P0: Add appointment-type disable/pause

Appointment types need a reversible off state. Delete is destructive and should not be the only way to remove a type from the public page.

Recommended controls:

- `Pause`: hides the type from the public page, keeps its link/history, marks local changes pending publish.
- `Resume`: returns it to the public page.
- `Delete`: only in a confirmation dialog, blocked or strongly warned when there are historical requests.
- `Duplicate`: keeps a new draft/paused copy until published.

Card badges should show `Live`, `Changed`, `Draft`, `Paused`, `No slots`, or `Broken`.

### P1: Make page customization a first-class native task

The docs say safe customization files are:

- `templates/booking-site/content/profile.md`
- `templates/booking-site/content/appointment-types/*.md`
- `templates/booking-site/content/default-copy.json`
- `templates/booking-site/assets/styles.css`

Users should not have to know that from docs. The native app should expose:

- `Customize page` section.
- `Profile and copy` fields for common copy.
- `Theme` controls for accent, background, surface, text, radius, and button style.
- `Open safe files in Finder`.
- `Open CSS`.
- `Preview local page`.
- `Regenerate from app settings`.
- `Run page safety check`.
- `Protected protocol files` disclosure that names files the app should not let an AI edit without explicit warning.

This directly addresses the user confusion about customizing the HTML page.

### P1: Turn Vercel into a guided deployment flow

The app should offer two paths:

- `Guided Vercel deploy`: open a Deploy Button URL with required environment variable names and safe defaults for non-secret values. The user fills `INBOX_ADMIN_TOKEN` and `BLOB_READ_WRITE_TOKEN`; the app then asks for or detects the deployment URL.
- `Vercel inbox`: enter a Vercel token and project ID/name, deploy, then verify.

If the app uses `VERCEL_ACCOUNT_TOKEN` or a user-entered Vercel token, it should:

- create or update the project
- set environment variables
- deploy
- capture production URL
- show deployment status
- verify `/healthz`
- show whether `ALLOWED_ORIGIN` matches the GitHub Pages origin

Vercel environment variables apply to production/preview/development contexts, and production deploys come from `vercel --prod` or a push to the production branch. The UI needs to show which environment was configured.

### P1: Use a split view/workbench pattern for macOS and iPad

For macOS and iPad, use a `NavigationSplitView` shape:

- Sidebar: `Overview`, `Event Types`, `Public Page`, `Publish`, `Inbox`, `Requests`.
- Content list: appointment types or deployment checklist depending on section.
- Detail inspector: selected appointment type, selected deploy target, selected request.

This matches the task complexity better than a tall sheet. A sheet is appropriate for small scoped tasks; this workflow is prolonged, multi-step, and has remote state.

For iPhone, keep a `NavigationStack` with the same top-level sections as list rows. Each row pushes into the same detail content.

### P1: Replace generic text with status cards and action rows

Good row pattern:

- Left: SF Symbol and status label.
- Center: one-line summary plus timestamp/detail.
- Right: one primary next action.

Examples:

- `Public page` - `Live, changes pending` - "Last verified 2:04 AM. 3 local changes are not live." - `Publish`
- `Request inbox` - `Reachable` - "Vercel production, allowed origin matches." - `Import`
- `Event types` - `5 live, 1 paused` - "2 changed locally." - `Review`

Avoid paragraphs near buttons when a status row can encode the same information.

### P1: Make n=0, n=1, and n=5 states intentionally different

#### n=0 state

When there are zero appointment types:

- Show a clear empty state: "Create your first event type."
- Offer templates: `Intro call`, `Consultation`, `Office hours`, `Paid session` if payment becomes relevant later.
- Ask only for name, duration, and weekly hours.
- Keep publish disabled until at least one valid type exists.

#### n=1 state

When there is one appointment type:

- Treat the single type as selected by default.
- Show the editor immediately below a compact card.
- On the public page, consider skipping the appointment selection rail and going straight to date/time, with a compact selected-type header.

#### n=5 state

When there are five appointment types:

- Use a searchable/sortable list with badges.
- Show only name, duration, location, status, and share action in each row.
- Edit one selected type in a detail pane.
- Provide bulk visibility review: "5 event types will be live on the next publish."
- Avoid showing all weekly-hour details in the list; use summaries.

#### n=20 state

When there are many types:

- Add search by name/slug.
- Add filters: `Live`, `Changed`, `Draft`, `Paused`, `No slots`.
- Move duplicate/delete/disable into a contextual menu.
- Consider grouping by purpose or calendar target.

### P1: Peel the onion with progressive disclosure

Layer 1: readiness

- Is booking ready?
- What is the next action?
- What changed since live?

Layer 2: operational CRUD

- Create/edit/disable appointment types.
- Generate/preview page.
- Publish.
- Import/approve requests.

Layer 3: deployment details

- GitHub repository, branch, token permissions.
- Vercel project, environment variables, deployment URL.
- Cloudflare worker details.

Layer 4: protocol/security details

- Encryption key IDs.
- Inbox IDs/share IDs.
- Signed slot token version.
- Public artifact audit results.

Layer 5: advanced recovery

- Rotate inbox secrets.
- Recreate local key material.
- Republish all files.
- Clear stale request duplicates.
- View raw generated files.

The current UI exposes some layer 3 details too early while hiding layer 1 evidence.

### P2: Improve public page IA

The public page should mirror the management IA enough that the user understands what they are editing.

Recommended changes:

- For one appointment type, start directly on date/time with a compact selected-type header.
- For multiple appointment types, show cards in a denser grid and reserve blank space less aggressively.
- Replace the huge timezone select with a collapsed button/menu: `America/Los Angeles (PDT) Change`. Use search when opened.
- Never show fixture/demo times like `2:01 AM` unless the user's configured weekly hours genuinely allow that.
- Add a no-slots state per appointment type: "No times are available right now" plus fallback contact/copy if configured.
- Add a preview banner in local preview mode: "Local preview. Not live."

### P2: Update labels

Use `event type` or `appointment type` consistently. The code currently uses appointment type, the user references appointment types, and booking products often use event type. Pick one product term.

Recommended native labels:

- `Event Types`
- `Public Page`
- `Publish`
- `Request Inbox`
- `Requests`
- `History`
- `Pause event type`
- `Publish changes`
- `Verify live page`
- `Preview local page`
- `Open page files`

Avoid:

- `Generate page files` when the action generates local files.
- `Verify page` without saying whether it verifies URL reachability or latest version.
- `Relay` in primary UI; keep it in docs/advanced protocol detail.
- `Needs check`; say `Not checked` or `Check required`.

### P2: Improve iconography

Use SF Symbols consistently:

- Booking workspace: `calendar.badge.plus`
- Event Types: `list.bullet.rectangle`
- Add event type: `plus`
- Live page: `globe`
- Local page files: `folder`
- Generate page files: `doc.text`
- Preview local page: `eye`
- Publish changes: `square.and.arrow.up`
- Verify live page: `checkmark.seal`
- Changed locally: `pencil.and.outline`
- Draft: `doc.badge.clock`
- Paused/disabled: `pause.circle`
- Broken/failed: `exclamationmark.triangle`
- Request inbox: `tray`
- Import requests: `tray.and.arrow.down`
- Test request: `paperplane`
- Copy link: `link`
- Open external link: `arrow.up.right.square`
- Secure/private: `lock.shield`
- Token/key: `key`
- History: `clock.arrow.circlepath`
- More actions: `ellipsis.circle`

Use icons to distinguish object types and lifecycle states, not as decoration.

## Anti-patterns to avoid

- Do not create separate setup and settings flows that edit the same data.
- Do not call a page published unless the live site is serving the expected version.
- Do not make users infer deploy state from raw URL fields.
- Do not hide required deployment variables in prose.
- Do not expose secret/token fields before the user chooses a deployment path.
- Do not make destructive delete the only way to remove an appointment type from the live page.
- Do not mutate stable appointment IDs just because the public slug changed.
- Do not show all advanced values in the top-level overview.
- Do not put a long timezone list in the primary page flow.
- Do not make local file generation sound like public deployment.
- Do not rely on HTTP reachability alone as verified.

## Proposed direction

### Product model

Treat booking as four linked resources:

- `EventType`: user-created booking offer with visibility, slug, duration, location, availability, questions, and auto-accept policy.
- `PublicPage`: profile, theme, copy, generated artifacts, live URL, and version fingerprint.
- `RequestInbox`: deployment provider, URL, allowed origin, health, admin import credentials, and relay status.
- `BookingRequest`: imported encrypted request lifecycle, approval/decline side effects, and history.

### IA

Use one Booking workspace with top-level navigation. Start every section with status and next action. Keep all CRUD and deployment work inside that workspace.

### State strategy

Create a `BookingPublicationVersion` concept:

- local config hash
- generated artifact hash
- GitHub commit SHA
- public site config hash
- verified at timestamp

Then use this to power labels:

- `Live`
- `Live, changes pending`
- `Uploaded, waiting for Pages`
- `Verification failed`

### Deployment strategy

GitHub:

- Validate repository/token first.
- Generate files.
- Upload files.
- Show commit SHA.
- Poll or prompt for GitHub Pages delay.
- Fetch live public config.
- Compare fingerprint.

Vercel:

- Offer guided Deploy Button or app-managed deployment.
- Show exact required env vars.
- Verify production deployment URL.
- Verify `ALLOWED_ORIGIN`.
- Keep production/preview environment explicit.

### Customization strategy

Expose common customization in native UI and advanced customization as safe files:

- Native: public name, title, subtitle, accent color, background, button radius, privacy note, success copy.
- Files: Markdown/CSS/JSON safe file list.
- Guardrails: run template tests and public artifact audit before publish.

## Non-goals

- Do not turn the relay into a calendar backend.
- Do not publish raw busy intervals, calendar IDs, event IDs, account emails, provider tokens, private keys, or visitor plaintext.
- Do not require GitHub/Vercel accounts for reading the public booking page.
- Do not replace the privacy-first static site model with a hosted SaaS backend.
- Do not add payment, team scheduling, or round-robin scheduling as part of this UX pass.

## Priority and sequencing

1. Merge setup sheet and workspace into one Booking workspace IA.
2. Add the explicit page/inbox/event-type state model and version fingerprint.
3. Add appointment-type pause/resume plus per-card lifecycle badges.
4. Improve GitHub publish evidence and live verification.
5. Turn Vercel into a real guided deployment path.
6. Add native customization entry points and local preview.
7. Improve public page n=1/n=5 states and timezone control.

## Open questions

- Should the product term be `Event Type` or `Appointment Type`? The report recommends `Event Type`, but existing code and docs use `Appointment type`.
- Should paused event-type links return a public "not available" page or disappear from the public page entirely?
- Should slug changes preserve immutable internal IDs and leave old public slugs as redirects/aliases?
- Should app-managed Vercel deployment use a user-entered token, the repo `.env` token only for development, or only a Deploy Button handoff?
- Should GitHub Pages verification poll for a bounded window or leave the user with a `Check again` action because GitHub documents that publish can take minutes?

## Promotion trigger

Promoted on 2026-06-03 and completed through `docs/exec-plans/completed/2026-06-03-booking-ux-ia-refresh.md`. The plan covered the single Booking workspace, publication-version state model, appointment-type pause/resume, publish verification, and Vercel deploy flow as one coherent milestone set.

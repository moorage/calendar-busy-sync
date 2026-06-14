# Privacy-first booking pages

Status: first self-hosted slice implemented.

Calendar Busy Sync can now carry a privacy-first booking workstream without making this open-source app, GitHub, Cloudflare, Vercel, or any helper service a calendar-data custodian.

## User story

A user can prepare a Calendly-style booking page, publish it to their own GitHub Pages repository, and point it at their own encrypted request inbox. Visitors open a shareable URL without signing in. The browser encrypts the request before it leaves the page. The native app remains the only place that can decrypt the request, recheck live availability, and write a calendar event.

## Privacy contract

Public booking artifacts may contain:

- appointment type names, durations, buffers, and public descriptions
- public page copy and CSS theme values
- signed open-slot tokens
- a public encryption key
- public inbox URL, opaque inbox ID, and opaque share ID

Public booking artifacts must not contain:

- Google or Apple calendar IDs
- provider event IDs
- provider tokens or OAuth client secrets
- private keys or signing keys
- calendar account email addresses
- raw busy intervals
- plaintext booking requests

The encrypted request inbox may store:

- request IDs
- inbox IDs and share IDs
- timestamps and expiry values
- encrypted request envelopes
- generic abuse-control metadata such as IP-derived rate counters

The encrypted request inbox must not store:

- provider credentials
- calendar credentials
- decrypted visitor names, emails, or answers
- calendar IDs or event IDs
- calendar availability decisions

## Booking workspace

The app now uses one native Booking workspace instead of a separate setup sheet and steady-state settings flow. The workspace sections are:

- `Overview`: readiness checklist and the next best action.
- `Appointment Types`: create, duplicate, edit, pause, resume, or delete appointment types.
- `Public Page`: native profile/theme fields, safe customization context for profile, appointment Markdown, copy, and CSS, local preview, and protected protocol-file guidance.
- `Publish`: local generation, GitHub upload, GitHub Pages serving, and live-version verification.
- `Request Inbox`: encrypted inbox URL, admin token, health checks, allowed-origin evidence, and test requests.
- `Requests`: imported pending, approved, declined, unavailable, and expired booking requests.

The Booking setup action opens the workspace Overview checklist. The checklist shows whether page files exist, whether a public URL is configured, whether the served page matches the latest generated version, whether an inbox is connected, and whether a test request has completed. Status labels distinguish `Generated locally`, `Uploaded, waiting for Pages`, `Live`, `Live, changes pending`, `Verification failed`, and `Disabled`; `Live` requires the served `public/site-config.json` fingerprint to match the latest generated fingerprint, not just an HTTP 2xx response.

Appointment types have a reversible paused state. Paused types remain visible in native management and history, but they are omitted from public `site-config.json`, public availability, and share-link actions until resumed and republished. Duplicated appointment types start paused so copied drafts do not accidentally appear live. Slug edits preserve the stable appointment ID and request history. Each appointment type also owns how far out bookers can see availability; the native editor caps that horizon at three months, and older saved appointment types default to 14 days.

When automatic acceptance is enabled, imported requests are accepted only after the native app decrypts the request, validates the signed slot, rechecks live availability, and writes the calendar event.

Public-page customization has two layers. Common fields are native: public name, page title, subtitle, timezone, accent color, background color, and text color. These values feed generated `site-config.json`, generated HTML metadata, and the local/public fingerprint. Deeper customization remains file-based through an app-owned editable template folder surfaced in the Public Page workspace; protocol-sensitive JavaScript and generated public JSON stay protected because they carry encryption, signing, and request-flow behavior.

When iCloud shared settings are enabled, native Booking setup roams across the user's installs through the same non-secret shared configuration path as calendar selections. That includes appointment type definitions, page and inbox URLs, GitHub/Vercel setup metadata, native profile/theme fields, selected appointment type, and automatic-approval preferences. It does not include inbox admin tokens, booking private keys, slot-signing secrets, deploy-key private keys, generated page-file paths, or the editable HTML/CSS/template folder; those stay local to each device.

GitHub Pages publishing is root-only once repository settings and a repository deploy key are configured. The app expects a dedicated empty repository, publishes generated booking artifacts at repository root over Git SSH, and blocks upload when the root already contains files outside the current generated artifact set. Manual publish and the macOS background polling loop both regenerate local booking artifacts for every active appointment type across each type's configured availability horizon, clone the repository with the stored deploy-key private key, skip byte-identical generated files, and commit/push only new or changed generated files. If another app instance or agent changed generated booking files in the repository, the native app overwrites them with the current local source of truth and records a warning in the Booking evidence/audit trail instead of failing the publish as a conflict. iOS can generate and verify page files but does not perform app-managed GitHub publishing in this milestone.

## Template Contract

The developer seed template lives in `templates/booking-site/` and is bundled into the app. End users do not need the source repository. The Mac app seeds a persistent editable template folder in Application Support, exposes that folder in the Public Page workspace, and provides an `Open template folder` action. The app must not overwrite this editable folder after it exists.

The generated page-files folder is separate from the editable template folder. `Generate page files` copies the editable template folder into the generated output folder, then overwrites only generated protocol artifacts such as `public/site-config.json` and `public/availability/slots.json`. Users edit the template folder, then generate page files to preview or publish.

Safe customization files:

- `content/profile.md`
- `content/appointment-types/*.md`
- `content/default-copy.json`
- `assets/styles.css`

Protected protocol files:

- `assets/app.js`
- `public/site-config.json`
- `public/availability/*.json`

Use the app's `Run safety check` action before publishing from the Mac app. Developers working from a source checkout can also run `scripts/test-booking-site`; it verifies that the page still encrypts before network submission and does not add third-party runtime scripts.

The generated public page must handle these visitor states:

- n=0 active appointment types: show `Booking is paused` and keep the request form hidden.
- n=1 active appointment type: auto-select it, hide the side rail, and present date/time selection as the main task.
- n=5 active appointment types: keep appointment cards compact and scannable.
- n=20 active appointment types: keep the appointment list scroll-contained so the scheduling pane remains usable.
- no available slots for a selected appointment type: keep the appointment context visible and show an explicit no-times state instead of a broken form.
- Timezone selection: keep the control available inside a disclosure instead of letting the full timezone list dominate the page.
- Local preview: show a visible preview banner when opened from `file:`, `localhost`, or `127.0.0.1` so users do not confuse draft files with the live public page.
- Generated demo slots: use standard 15-minute scheduling increments.

## Relay contract

Both relay templates implement:

- `POST /v1/inboxes/:inboxId/requests`
- `GET /v1/inboxes/:inboxId/requests?cursor=...`
- `DELETE /v1/inboxes/:inboxId/requests/:requestId`
- `GET /healthz`

The relay is blind. It accepts, lists, and deletes encrypted envelopes. It cannot read calendars, exchange OAuth tokens, inspect request contents, or decide whether a slot is still open.

`GET /healthz` returns non-secret setup evidence:

- `ok`
- `allowedOrigin`
- `storage`

The native app compares `allowedOrigin` with the configured public booking-page origin. The Request Inbox status is `Configured` when a URL is saved, `Reachable` when health responds but the admin token is missing, `Allowed-origin mismatch` when the relay origin does not match the page origin, and `Ready` only when health is reachable, the origin matches when reported, and the admin token is present.

Guided Vercel setup is an evidence-first workflow. The app shows the required environment variables, captures the production inbox URL and admin token, checks `/healthz`, and sends/imports encrypted test requests. The native app does not create Vercel projects or mutate Vercel environment variables as part of this spec.

## Acceptance

- Booking copy and native icon choices are centralized in Swift registries.
- Markdown appointment parsing rejects duplicate slugs, missing durations, unsupported question types, and secret-looking public values.
- Signed slot tokens include appointment type, slot ID, start/end, generated-at, expiry, nonce, and signing-key version.
- Availability uses half-open interval overlap semantics, so a busy event that starts exactly when a slot ends does not suppress the preceding slot.
- The static page uses Web Crypto before any request submission fetch.
- Cloudflare and Vercel relay templates include the same inbox API and explicit abuse controls.
- The Vercel relay template rewrites `/healthz` and `/v1/...` public routes to Vercel's `/api/...` functions and stores only encrypted envelopes in Blob storage.
- Relay health checks expose only non-secret `allowedOrigin` and storage-backend evidence so users can tell whether CORS is configured for the current public page.
- Docs explain GitHub Pages publishing, Cloudflare deployment, Vercel deployment, AI customization, and video-script generation.
- The settings `Set up booking` / `Continue setup` button opens the Booking workspace Overview instead of running hidden background work.
- Published page verification compares the served public configuration fingerprint with the generated fingerprint before showing `Live`.
- Paused appointment types stay out of public config and generated slots while preserving native history and identity.
- Native public-page fields generate fresh preview files before opening local preview, so previews reflect the latest copy and theme edits.
- Configured GitHub publishing skips commits when public booking artifacts already match GitHub, and remote generated-file drift is visible as a warning rather than a hard failure.

# Shared Google Account Handoff via iCloud

## Purpose / Big Picture

Let iCloud shared configuration carry the intended Google account roster, not just the selected calendar IDs, so one device can tell the others which Google accounts should participate. The app must still keep Google auth local to each device, but when a shared Google account appears or disappears in iCloud settings, the current device should present a convenient one-step flow to connect that same account locally or remove the now-stale local account with the same selection settings applied.

This is a trust-sensitive bridge between shared non-secret settings and local secrets. The app must not sync tokens, archived `GIDGoogleUser` blobs, or keychain state through iCloud. Instead, it should sync only the non-secret identity and selection metadata needed to guide the local setup flow.

## Progress

- [x] 2026-04-20T20:02Z inspect the current shared iCloud configuration, Google secure-store boundary, and Google account roster UI to identify what is already synced and what is missing for cross-device account handoff
- [x] 2026-04-20T20:10Z add a shared Google account-descriptor layer to the iCloud payload and local settings model, including migration from the existing selected-calendar-only payload
- [x] 2026-04-20T20:18Z extend the Google account roster UI so a device can see shared-but-not-local accounts, locally connected accounts removed elsewhere, and one-tap connect/remove actions for those cases
- [x] 2026-04-20T20:31Z wire the local connect/remove flows so shared account descriptors preserve calendar choice when possible, then update docs and run focused validation
- [x] 2026-04-20T21:12Z validate the new shared-handoff flow with unit coverage, macOS build/smoke, and docs checks

## Surprises & Discoveries

- 2026-04-20: the current iCloud payload already syncs `googleSelectedCalendarIDs`, but it does not sync the intended Google account roster, so another device has no way to know which missing account those selected calendar IDs belong to.
- 2026-04-20: the secure Google roster is cleanly separated from settings today. `GoogleAccountStore` persists full local account/session payloads in the keychain, while `AppModel` stores selection state in `UserDefaults` and iCloud, so the missing feature is a shared descriptor layer rather than a credential migration.
- 2026-04-20: a remote Google-account removal cannot safely auto-delete local secrets without user involvement. The shared flow should mark the account as removed elsewhere and offer a local one-step removal, while shared calendar participation is still removed immediately by the synced selection state.
- 2026-04-20: matching a shared Google account on another device cannot rely on the stored Google account ID alone. Email matching is the practical cross-device fallback, and the selected calendar display name is needed as a human-friendly recovery hint when only the account handoff has already synced.

## Decision Log

- 2026-04-20: keep Google credentials and archived Google user payloads device-local; sync only non-secret Google account descriptors such as stable account ID, email, display name, custom-OAuth mode, and selected-calendar metadata.
- 2026-04-20: treat the iCloud Google-account roster as the shared desired state for participating accounts. A device without a local authorization for one of those accounts should render a guided “connect locally” row rather than a blank missing selection.
- 2026-04-20: do not silently delete a local Google account when another device removes it from the shared roster. Instead, remove its shared participation immediately and present a convenient “remove here” affordance for the local secure-store cleanup.
- 2026-04-20: preserve existing selected-calendar behavior by syncing both the stable calendar ID and a human-readable calendar name so a newly connected device can resolve the same destination calendar even if it needs a fallback beyond the raw ID.
- 2026-04-20: if shared settings are disabled on the current device, the Google settings UI should collapse back to the purely local roster instead of showing cross-device handoff rows.

## Outcomes & Retrospective

- Shared iCloud configuration now carries a non-secret Google account descriptor roster alongside selected-calendar IDs, and older payloads still decode without that field.
- The Google settings section now renders a merged roster of locally connected accounts, shared accounts waiting for local sign-in, and local accounts removed from the shared roster elsewhere.
- Cross-device handoff keeps Google credentials device-local while preserving the chosen destination calendar through the local reconnect flow whenever the account and calendar can be resolved again.
- Validation passed with `./scripts/test-unit`, `./scripts/build --platform macos`, `./scripts/test-ui-macos --smoke`, `./scripts/build --platform ios --device-class both`, `./scripts/test-ui-ios --device both --smoke`, `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-google-account-handoff-icloud.md`, and `python3 scripts/knowledge/check_docs.py`.

## Context and Orientation

Relevant code paths:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/SharedAppConfiguration.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleSignInService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/GoogleAccountCardModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `.agents/DOCUMENTATION.md`

Current behavior:

- local Google auth/account state lives only in `GoogleAccountStore`
- iCloud shared settings sync `googleSelectedCalendarIDs` keyed by local Google account ID, plus `activeGoogleAccountID`
- the UI only renders locally connected Google accounts
- if a shared configuration arrives on another device with Google selected-calendar IDs for an account that is not locally connected, the device has no UI affordance that explains which account is missing or how to reconnect it with the same settings

Target behavior:

- iCloud shared settings include a non-secret Google account descriptor roster
- a device with shared settings enabled can render:
  - locally connected shared Google accounts
  - shared Google accounts that still need local sign-in on this device
  - locally connected Google accounts that were removed from the shared roster elsewhere
- when the user connects a shared Google account locally, the app reuses the shared selected-calendar setting for that account
- when the user removes a locally connected account that was already removed from the shared roster elsewhere, the cleanup is one tap and uses the same remove flow as a normal local removal

Assumptions:

- Google account IDs and/or emails are stable enough across devices to match a newly connected local account to the shared descriptor
- Google calendar IDs remain stable within the same Google account across devices; the human-readable calendar name is a fallback hint, not the primary key
- iCloud-shared configuration remains the shared desired state only when `isSharedConfigurationEnabled` is true on the current device

## Plan of Work

1. Extend the shared iCloud configuration schema with a non-secret Google account-descriptor roster that can describe intended participating accounts across devices.
2. Add a shared/local Google roster merge layer that derives the account-management UI state from:
   - locally authorized Google accounts
   - shared desired Google account descriptors
   - shared selected-calendar metadata
3. Add per-device handoff actions:
   - connect a shared-but-not-local account using the shared email as a sign-in hint
   - remove a local account that was removed from the shared roster elsewhere
4. Update the settings UI, tests, and docs to reflect the new cross-device account handoff flow.

## Concrete Steps

1. Patch `Calendar Busy Sync/Calendar Busy Sync/App/Shared/SharedAppConfiguration.swift`:
   - add a `SharedGoogleAccountDescriptor` type with:
     - stable account ID
     - email
     - display name
     - custom OAuth flag
     - selected calendar ID
     - selected calendar display name
   - extend `SharedAppConfiguration` to carry a descriptor array while remaining decodable from older payloads that only have `googleSelectedCalendarIDs`
2. Patch `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`:
   - persist/load the shared Google account-descriptor roster locally
   - include it in `currentSharedConfiguration`
   - apply it from remote shared settings
   - derive helper state for:
     - shared account descriptors not yet connected locally
     - local accounts no longer present in the shared descriptor roster
   - add a connect flow that uses the shared email as the Google sign-in hint and preserves the shared calendar selection after local authorization succeeds
3. Add a small Google roster merge model under `Calendar Busy Sync/Calendar Busy Sync/App/Shared/`:
   - create typed row models for:
     - local shared accounts
     - shared accounts awaiting local connection
     - local accounts removed from the shared roster
   - keep the state computation out of `ContentView.swift`
4. Patch `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`:
   - render the merged Google account roster
   - show a clear local-connect action for shared accounts missing on this device
   - show a one-tap local-remove action for accounts removed elsewhere
   - preserve the existing calendar picker and refresh path for fully connected local rows
5. Patch `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`:
   - cover shared-configuration decoding/migration
   - cover merged Google roster state for:
     - local+shared account match
     - shared-only account
     - local-only removed-elsewhere account
   - cover calendar-selection preservation helpers for a newly connected local account
6. Update:
   - `README.md`
   - `ARCHITECTURE.md`
   - `docs/product-specs/calendar-sync.md`
   - `.agents/DOCUMENTATION.md`

## Validation and Acceptance

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-20-google-account-handoff-icloud.md
./scripts/test-unit
./scripts/build --platform macos
./scripts/test-ui-macos --smoke
python3 scripts/knowledge/check_docs.py
```

Acceptance criteria:

- iCloud shared settings remember which Google accounts participate and which calendar is selected for each one
- a second device with shared settings enabled can show a shared Google account that is not yet locally connected, with a clear connect action
- after local connection, the app applies the shared selected-calendar choice for that account when possible
- if a shared Google account is removed on another device, the current device stops treating it as a shared participant and offers a one-step local removal affordance
- Google auth tokens, archived Google user payloads, and other secrets remain device-local and never enter the shared iCloud payload

## Idempotence and Recovery

- shared Google account descriptors are additive metadata over the existing local secure store; if the new descriptor layer fails to load, the local Google accounts still function as they do today
- older iCloud payloads without Google account descriptors should still decode and fall back to the legacy selected-calendar-only behavior
- rollback can remove the shared descriptor layer and merged roster UI while keeping the existing local Google account store intact
- if the user connects the wrong Google account on a device, the current local remove flow remains the recovery path

## Artifacts and Notes

- user-visible workflow to verify manually after implementation:
  - connect a Google account on Device A
  - choose a destination calendar
  - open Device B under the same Apple ID and shared-settings enabled
  - confirm Device B shows a row telling the user to connect that same shared account locally
  - connect the account on Device B and confirm the same destination calendar is selected automatically when available
  - remove the account on Device A and confirm Device B marks it as removed elsewhere with a local remove action

## Interfaces and Dependencies

- `Foundation.NSUbiquitousKeyValueStore`
- `UserDefaults`
- `GoogleSignIn`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleSignInService.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/SharedAppConfiguration.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/GoogleAccountCardModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`

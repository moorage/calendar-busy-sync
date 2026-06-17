# Keychain Prompt Regression

## Purpose / Big Picture

Calendar Busy Sync should not ask the user to unlock the app credential vault during routine polling, sync, or booking checks after the user has already signed in and the Mac session is unlocked. The June 15 single-vault change consolidated Google and Booking secrets into one Keychain item, but it also made the production item require local user presence for reads. That means macOS can prompt again whenever the app reads credentials after the authentication reuse window expires.

The user-visible behavior after this fix is:

- app-owned Google and Booking secrets stay in Keychain-backed secure storage
- routine app reads use normal Keychain availability instead of repeated Touch ID, Apple Watch, or password prompts
- existing local-auth-protected vault items are migrated to the normal Keychain policy after one successful read
- legacy Google and Booking per-domain item migration remains intact

## Progress

- [x] 2026-06-17T19:46Z traced repeated prompts to `AppCredentialVault` using `.userPresence` plus a 300-second `LAContext` reuse duration
- [x] 2026-06-17T19:46Z created this active ExecPlan for the credential prompt regression
- [x] 2026-06-17T20:05Z changed `AppCredentialVault.shared` to default to device-local Keychain availability instead of local user presence
- [x] 2026-06-17T20:05Z updated credential-vault tests to exercise the production default Keychain policy
- [x] 2026-06-17T20:05Z updated architecture, security, and implementation notes to document the quiet routine-read behavior
- [x] 2026-06-17T20:57Z validated focused credential-vault tests, ExecPlan checks, docs checks, and whitespace checks

## Surprises & Discoveries

- 2026-06-17: The code reused one `LAContext`, but set `touchIDAuthenticationAllowableReuseDuration` to 300 seconds, so the previous implementation could never provide "unlock once and stay quiet" behavior.
- 2026-06-17: The completed June 15 plan optimized for one protected vault prompt instead of independent prompts, but routine sync and booking paths read the same vault often enough that local-user-presence protection is too noisy for this app.
- 2026-06-17: The app can keep the legacy local-user-presence read path isolated to migration. Normal reads now set `kSecUseAuthenticationUISkip`, so an old protected item is detected before the explicit migration read asks the user to unlock it.

## Decision Log

- 2026-06-17: Use normal Keychain item protection for the app credential vault. The vault remains in platform secure storage, while the app stops requiring local authentication for every credential read.
- 2026-06-17: Keep the local-user-presence policy available only as a legacy/migration read path so an already-protected vault can be read once and rewritten under the normal policy.

## Outcomes & Retrospective

Implemented the prompt regression fix. `AppCredentialVault.shared` now defaults to `.deviceKeychain`, which writes the app-owned Google and Booking vault with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` instead of `.userPresence`. Routine reads skip authentication UI, so background polling and booking checks do not repeatedly ask for Touch ID, Apple Watch, or the login password.

The old `.localUserPresence` path remains as a migration-only compatibility path. If a user already has the June 15 protected vault item, the first read after this fix detects that normal no-UI access is not possible, asks once through the legacy `LAContext`, decodes the payload, and rewrites the vault with the device-local Keychain policy.

Validation passed:

```bash
xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-keychain-prompt-regression -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testGoogleAccountStoreUpsertsAndRemovesAccounts' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialVaultMigratesBookingAndGoogleSecretsIntoOneItem' test
python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-17-keychain-prompt-regression.md
python3 scripts/knowledge/check_docs.py
git diff --check
```

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppCredentialVault.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSecretStore.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `README.md`
- `ARCHITECTURE.md`
- `docs/SECURITY.md`
- `.agents/DOCUMENTATION.md`

Previous behavior:

- `AppCredentialVault.shared` defaults to `.localUserPresence`.
- New vault items are created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` plus `.userPresence`.
- Reads pass a shared `LAContext` with a 300-second reuse duration.

Target behavior:

- `AppCredentialVault.shared` defaults to normal Keychain protection.
- New and updated production vault items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- If the old protected item is found, the app reads it once with the legacy policy and rewrites it using normal Keychain protection.

## Plan of Work

1. Change the production vault access policy from local user presence to normal Keychain protection.
2. Add a focused migration path that reads an existing protected item and rewrites it without user-presence access control.
3. Update tests to cover the new default policy and migration behavior without invoking biometric UI.
4. Update docs to remove the claim that routine app-owned credential storage is protected by local user presence.
5. Validate with focused credential tests, ExecPlan checks, docs checks, and whitespace checks.

## Concrete Steps

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
rg -n "AppCredentialVault|localUserPresence|touchIDAuthenticationAllowableReuseDuration" "Calendar Busy Sync/Calendar Busy Sync" "Calendar Busy Sync/Calendar Busy SyncTests" README.md ARCHITECTURE.md .agents/DOCUMENTATION.md docs
```

Implement:

- update `AppCredentialVaultAccessPolicy`
- update `AppCredentialVault` read/write queries and migration behavior
- update focused credential-vault tests
- update documentation references to the credential prompt behavior

Validate:

```bash
xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-keychain-prompt-regression -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testGoogleAccountStoreUpsertsAndRemovesAccounts' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialVaultMigratesBookingAndGoogleSecretsIntoOneItem' test
python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-17-keychain-prompt-regression.md
python3 scripts/knowledge/check_docs.py
git diff --check
```

## Validation and Acceptance

Acceptance criteria:

- routine `AppCredentialVault.shared` reads no longer request local user presence
- existing `.userPresence` vault items can be read once and rewritten under the normal Keychain policy
- Google and Booking stores keep their public protocols and legacy migrations intact
- docs correctly describe credentials as Keychain-backed local storage without promising repeated local authentication

## Idempotence and Recovery

The migration is idempotent:

- if the normal vault item already exists, the app uses it directly
- if only a legacy protected item exists, the app reads it and rewrites the same account using the normal policy
- if no vault exists, the app creates one only when a store saves or migrates legacy domain-specific secrets

Rollback:

- restore `AppCredentialVault.shared` to the local-user-presence access policy
- remove the protected-item rewrite migration
- no destructive cleanup of stored credentials is needed

## Artifacts and Notes

Expected artifacts:

- `artifacts/DerivedData-keychain-prompt-regression`

No credential payload bytes, tokens, or Keychain item values should be logged or written to checked-in files.

## Interfaces and Dependencies

Apple frameworks:

- `Security` for Keychain storage
- `LocalAuthentication` only for reading existing protected vault items during migration

Internal interfaces:

- `AppCredentialVaultStoring`
- `BookingSecretStoring`
- `GoogleAccountStoring`

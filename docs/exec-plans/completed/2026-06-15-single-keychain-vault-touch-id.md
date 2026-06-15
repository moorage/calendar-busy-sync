# Single Keychain Vault With Local Authentication

## Purpose / Big Picture

Calendar Busy Sync currently stores booking secrets and Google calendar account archives in separate Keychain items. On macOS, that can surface as multiple Keychain password prompts: one for Booking and one for Calendars. The goal is to make app-owned credentials unlock through one app-owned Keychain vault item, protected by local authentication so supported Macs can show Touch ID, Apple Watch, or the login password fallback.

The user-visible behavior after this change is:

- the app stores booking secrets, Vercel token, inbox admin token, GitHub deploy-key private key, and Google account archives under one Keychain item
- existing users are migrated from the older per-domain Keychain items without losing credentials
- app-owned credential reads use one protected Keychain item instead of multiple independent items
- on macOS hardware that supports it, the system can present Touch ID or Apple Watch for the protected vault instead of separate password prompts

## Progress

- [x] 2026-06-15T00:00Z inspect current booking and Google Keychain stores and confirm both app-owned stores use plain generic-password items
- [x] 2026-06-15T00:00Z create this active ExecPlan for the single-vault credential migration
- [x] 2026-06-15T07:09Z add `AppCredentialVault`, rewire Booking and Google stores to use it, and add legacy migration coverage
- [x] 2026-06-15T07:09Z validate focused credential-vault tests with `xcodebuild` against `artifacts/DerivedData-single-keychain-vault`
- [x] 2026-06-15T07:13Z validate the completed ExecPlan, docs control plane, and whitespace with repository scripts

## Surprises & Discoveries

- 2026-06-15: Both current app-owned stores use generic-password Keychain items without `SecAccessControl` or `LAContext`, so macOS has no basis to show Touch ID for them.
- 2026-06-15: `GoogleSignInService` still calls `GIDSignIn.sharedInstance.restorePreviousSignIn()` for SDK-managed sessions when available, but normal app startup clears the SDK session and restores archived Google users from `GoogleAccountStore`, so the app-owned archive is the main calendar credential prompt path to merge.
- 2026-06-15: The first migration test exposed an ordering bug: if Booking created the vault first, Google legacy accounts had to merge into an existing vault payload and then persist that merged payload. The migration helpers now save whenever a domain-specific legacy merge changes the vault.

## Decision Log

- 2026-06-15: Use one shared Codable vault payload instead of trying to coordinate authentication reuse across multiple Keychain items. One protected item is simpler to reason about and matches the user's request for one Keychain item.
- 2026-06-15: Keep the existing `BookingSecretStoring` and `GoogleAccountStoring` protocols stable. The migration is an implementation detail under the stores, not an AppModel contract change.
- 2026-06-15: Use `.userPresence` for production access control rather than a biometrics-only flag. That lets macOS choose Touch ID or Apple Watch when available while preserving the system password fallback for users without biometrics.

## Outcomes & Retrospective

Implemented the first single-vault credential slice. `BookingKeychainSecretStore` now reads and writes booking local secrets, inbox admin token, Vercel token, and GitHub deploy-key private key through `AppCredentialVault`. `GoogleAccountStore` now reads and writes archived Google account sessions through the same vault. Legacy Booking and Google Keychain items remain readable as migration sources and are left in place for downgrade safety.

Production vault writes use `SecAccessControl` with `.userPresence` and a shared `LAContext` prompt, so macOS can present Touch ID, Apple Watch, or the login password fallback for one protected vault item. Tests inject an unprotected vault policy to avoid biometric UI.

Focused validation passed:

```bash
xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-single-keychain-vault -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testGoogleAccountStoreUpsertsAndRemovesAccounts' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialVaultMigratesBookingAndGoogleSecretsIntoOneItem' test
```

Final documentation and whitespace validation passed:

```bash
python3 scripts/check_execplan.py docs/exec-plans/completed/2026-06-15-single-keychain-vault-touch-id.md
python3 scripts/knowledge/check_docs.py
git diff --check
```

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSecretStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `README.md`
- `ARCHITECTURE.md`
- `.agents/DOCUMENTATION.md`

Current storage:

- `BookingKeychainSecretStore` stores separate generic-password accounts under a `.booking` Keychain service.
- `GoogleAccountStore` stores archived Google users under a `.google-accounts` Keychain service.
- Both stores use `kSecAttrAccessibleAfterFirstUnlock` on iOS only and no explicit access control on macOS.

Target storage:

- `AppCredentialVault` stores one Codable payload under a single app service/account.
- The production vault writes with Keychain access control using local user presence.
- The old booking and Google items remain readable as migration sources only.

## Plan of Work

1. Add a shared credential-vault type with a single Codable payload, production local-auth access control, and test-configurable unprotected mode.
2. Rewire `BookingKeychainSecretStore` to read/write booking fields through the vault while migrating old per-account booking items when needed.
3. Rewire `GoogleAccountStore` to read/write Google accounts through the same vault while migrating the old Google account item when needed.
4. Add focused unit coverage for booking and Google migration into one vault.
5. Update docs and this ExecPlan with the new credential boundary and validation evidence.

## Concrete Steps

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
rg -n "SecItem|kSec|Keychain|GoogleAccountStore|BookingKeychainSecretStore" "Calendar Busy Sync/Calendar Busy Sync"
```

Implement:

- add `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppCredentialVault.swift`
- update `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSecretStore.swift`
- update `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- update focused tests in `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`

Validate:

```bash
xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-single-keychain-vault -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testGoogleAccountStoreUpsertsAndRemovesAccounts' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialVaultMigratesBookingAndGoogleSecretsIntoOneItem' test
python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-15-single-keychain-vault-touch-id.md
python3 scripts/knowledge/check_docs.py
git diff --check
```

## Validation and Acceptance

Acceptance criteria:

- a new install stores app-owned secrets under one shared Keychain item
- an existing install can read legacy booking and Google Keychain items and write them into the new shared vault
- existing store protocols and AppModel callers continue to compile
- production vault items are created with local-auth access control so macOS can present Touch ID/Apple Watch/login password for one item
- unit tests cover store behavior and migration without requiring biometric prompts in CI

## Idempotence and Recovery

The migration must be idempotent:

- if the shared vault already exists, stores use it as the source of truth
- if the shared vault does not exist, stores read legacy items and write a merged vault payload
- legacy items are left in place in the first implementation so a failed write or downgrade does not lose credentials

Rollback:

- restore the previous store implementations to read the old per-domain Keychain items
- leave the new shared vault item ignored; no destructive cleanup is required

## Artifacts and Notes

Expected artifacts:

- `artifacts/DerivedData-single-keychain-vault`
- xcodebuild output in the terminal session

No credentials, token values, or Keychain payload bytes should be written to logs or checked-in fixtures.

## Interfaces and Dependencies

Apple frameworks:

- `Security` for Keychain item storage
- `LocalAuthentication` for `LAContext` and user-presence authentication

Internal interfaces:

- `BookingSecretStoring`
- `GoogleAccountStoring`
- `BookingLocalSecrets`
- `StoredGoogleAccount`

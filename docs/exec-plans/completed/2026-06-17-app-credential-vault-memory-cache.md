# App Credential Vault In-Memory Cache

## Purpose / Big Picture

Calendar Busy Sync should not re-read app-owned Google and Booking secrets from Keychain every time the open app needs credentials. The app already stores those secrets in one Keychain-backed `AppCredentialVault` item, and current production items use normal device-local Keychain availability. However, repeated vault reads still hit Keychain during one app process, and legacy local-auth-protected items can still trigger an unlock while being migrated.

The desired behavior for this slice is:

- the first successful vault read in a running app decodes the Keychain payload and keeps that decoded payload in memory
- later reads in the same app process return the in-memory payload without another Keychain lookup
- successful writes update both Keychain and the in-memory payload
- token/account mutations remain durable in Keychain
- relaunching the app starts with an empty memory cache and reads Keychain again
- if a future credential path receives an auth/token failure and needs a fresh persisted view, it can invalidate the vault cache before retrying

## Progress

- [x] 2026-06-17T23:58Z create this active ExecPlan for the app credential vault memory cache
- [x] 2026-06-18T00:12Z add vault-level in-memory payload caching, explicit invalidation, write-through cache updates, and 401-triggered invalidation hooks for Google, Vercel, and relay token failures
- [x] 2026-06-18T00:25Z validate the focused credential-cache XCTest slice and update architecture/control-plane notes

## Surprises & Discoveries

- 2026-06-17: New app credential vault items already avoid repeated Touch ID by using device-local Keychain protection. The remaining repeated work is Keychain I/O inside one app process, plus legacy migration reads for older local-auth-protected items.
- 2026-06-18: Token-access failures surface through three app paths: Google Calendar API, Vercel deployment API, and relay admin-token calls. Only `401` is treated as credential-authentication failure; `403` can be a permission or scope problem and does not invalidate the cache.

## Decision Log

- 2026-06-17: Put the cache at the `AppCredentialVault` boundary rather than inside Google or Booking stores, so all app-owned credential payload reads share one consistency point.
- 2026-06-17: Cache only after a successful Keychain read or write. Do not cache Keychain read failures, corrupt payloads, or item-not-found results.
- 2026-06-17: Add an explicit invalidation method to the vault protocol so callers that detect credential invalidation can force the next read back through Keychain.

## Outcomes & Retrospective

Implemented a process-local cache inside `AppCredentialVault`. The first successful read or write stores the decoded credential payload in memory behind the existing vault lock; later reads in the same app process return that cached payload without another Keychain lookup. Successful saves update both Keychain and the cache. `invalidateCachedPayload()` clears only the in-memory value, leaving Keychain untouched, so the next read goes back to durable storage.

`GoogleAccountStore` and `BookingKeychainSecretStore` now expose cache invalidation through their protocols. `AppModel` invalidates the relevant cache on Google Calendar API `401`, Vercel deployment `401`, and relay admin-token `401` failures. Relaunching the app naturally starts with an empty cache.

Focused XCTest validation passed for cache reuse until explicit invalidation, write-through cache updates, and authentication-failure classification.

## Context and Orientation

Relevant files:

- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppCredentialVault.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/Booking/BookingSecretStore.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/GoogleAccountStore.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `.agents/DOCUMENTATION.md`

Existing behavior:

- `AppCredentialVault.shared` stores one local Keychain item containing Google account archives and Booking secrets.
- `BookingKeychainSecretStore` and `GoogleAccountStore` read and write through `AppCredentialVaultStoring`.
- `AppCredentialVault.shared` uses `.deviceKeychain` by default, and legacy local-user-presence items are migrated after one successful protected read.

## Plan of Work

1. Add an in-memory cached payload to `AppCredentialVault`, protected by the existing recursive lock.
2. Return the cached payload before building a Keychain read query.
3. Update the cache after successful `savePayload`, `updatePayload`, and legacy migration rewrite.
4. Add explicit cache invalidation to the vault protocol and implementation.
5. Add focused tests showing repeated loads avoid rereading Keychain until invalidated, and writes update the cached payload.
6. Update implementation notes with the new credential lifetime behavior.

## Concrete Steps

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

```bash
rg -n "AppCredentialVault|AppCredentialVaultStoring|loadPayloadIfPresent|savePayload|updatePayload" "Calendar Busy Sync/Calendar Busy Sync" "Calendar Busy Sync/Calendar Busy SyncTests"
```

Implement:

- update `AppCredentialVaultStoring` with `invalidateCachedPayload()`
- add a private `cachedPayload` field to `AppCredentialVault`
- update load/save/update/migration paths to maintain the cache
- add focused XCTest coverage in `Calendar_Busy_SyncTests`

Validate:

```bash
xcodebuild -project 'Calendar Busy Sync/Calendar Busy Sync.xcodeproj' -scheme 'Calendar Busy Sync' -configuration Debug -derivedDataPath artifacts/DerivedData-credential-vault-cache -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialVaultCachesDecodedPayloadUntilInvalidated' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialVaultSaveUpdatesCachedPayload' -only-testing:'Calendar Busy SyncTests/Calendar_Busy_SyncTests/testCredentialCacheInvalidationClassifiesAuthenticationFailures' test
python3 scripts/check_execplan.py docs/exec-plans/active/2026-06-17-app-credential-vault-memory-cache.md
python3 scripts/knowledge/check_docs.py
git diff --check
```

## Validation and Acceptance

Acceptance criteria:

- a vault instance that has successfully read a payload serves repeated loads from memory until invalidated
- invalidating the cache makes the next load read the latest Keychain payload
- successful saves update the cache immediately
- no secret values are logged or written to checked-in files
- Google and Booking store protocols continue to use the same app vault boundary

## Idempotence and Recovery

The change is process-local and reversible:

- relaunching the app clears the in-memory cache naturally
- Keychain remains the durable source of truth
- `invalidateCachedPayload()` allows a caller to force a fresh Keychain read after token/auth failures or external credential repair
- rollback removes the cache field and invalidation method without changing persisted Keychain payload format

## Artifacts and Notes

Expected validation artifacts:

- `artifacts/DerivedData-credential-vault-cache`

No credential payload bytes, tokens, private keys, or archived Google user data should be printed, logged, or committed.

## Interfaces and Dependencies

Apple frameworks:

- `Security` for durable Keychain storage
- `LocalAuthentication` only for legacy local-user-presence migration reads

Internal interfaces:

- `AppCredentialVaultStoring`
- `BookingSecretStoring`
- `GoogleAccountStoring`

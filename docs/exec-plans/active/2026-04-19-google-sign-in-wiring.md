# Google Sign-In Wiring

## Purpose / Big Picture

Wire the app's existing settings shell to a real Google Sign-In integration so Calendar Busy Sync can restore a signed-in Google account, let the user connect or disconnect an account from the main settings surface, and make the default Google OAuth app from `client.apps.googleusercontent.com.plist` actually usable on macOS, iPhone, and iPad.

The work must also reconcile a product constraint: Google still requires the app's OAuth client ID and reversed client-ID URL scheme to be declared in `Info.plist`, which means the default bundled Google app can be fully live, but arbitrary runtime user-supplied iOS/macOS client IDs cannot be swapped in transparently unless the callback scheme is already baked into the app. The Advanced override remains user-visible, but the implementation must fail clearly and explain the boundary instead of pretending arbitrary custom native client IDs are guaranteed to work.

## Progress

- [x] 2026-04-19T17:08Z inspect the current app shell, harness scripts, `.env`, and Google client plist
- [x] 2026-04-19T17:17Z verify Google's current iOS/macOS SDK requirements for client ID, URL scheme, restore flow, and optional server client ID
- [x] 2026-04-19T17:39Z patch the Xcode project, harness wrappers, plist sync, and entitlements for Google Sign-In
- [x] 2026-04-19T17:49Z implement live Google auth state, restore, connect, disconnect, and settings-driven configuration resolution
- [x] 2026-04-19T18:00Z update the settings UI, tests, docs, and documentation log, then run build/test/docs verification

## Surprises & Discoveries

- 2026-04-19: the repo already has persisted Advanced settings for a custom Google OAuth app, but no provider integration yet, so the first live auth slice needs to connect pre-existing settings and audit-trail surfaces instead of inventing them.
- 2026-04-19: Google's current iOS/macOS docs still require `GIDClientID` plus a custom URL scheme derived from the reversed client ID in `Info.plist`, so a shipped build cannot guarantee arbitrary runtime custom native client IDs without a matching predeclared callback scheme.
- 2026-04-19: the checked-in `client.apps.googleusercontent.com.plist` is aligned to the app bundle ID `com.matthewpaulmoore.Calendar-Busy-Sync`, which makes it a safe default integration target for this repo.
- 2026-04-19: placing the generated `Info.plist` inside the file-system-synchronized app folder caused Xcode to treat it as a copied resource, so the stable fix was to generate it at the project root instead.
- 2026-04-19: the current GoogleSignIn SDK uses `signIn(withPresenting:hint:additionalScopes:)` on both macOS and iOS async paths, even though the reference docs still distinguish the macOS concept as a presenting window.

## Decision Log

- 2026-04-19: integrate the default bundled Google OAuth client as the primary live path and expose custom-client mode with explicit validation/limitations rather than removing the setting or silently ignoring it.
- 2026-04-19: use Swift Package Manager for `GoogleSignIn-iOS` and a real app `Info.plist` file instead of trying to keep `GENERATE_INFOPLIST_FILE = YES`, because the URL-scheme callback requirement is clearer and less brittle in source control.
- 2026-04-19: keep the current app scenario-backed for calendar data and sync previews; only the authentication layer becomes live in this slice.
- 2026-04-19: add an explicit macOS keychain entitlement path during the Xcode patch so Google credential restore is not iOS-only.

## Outcomes & Retrospective

Implemented:

- `GoogleSignIn-iOS` is now linked into the app target through Swift Package Manager
- `scripts/sync-google-client-config.py` now syncs `.env` + `GOOGLE_CLIENT_PLIST_PATH` into `Calendar Busy Sync/Info.plist` and `Calendar Busy Sync/Calendar Busy Sync/DefaultGoogleOAuth.plist`
- the app restores previous Google sign-in state on launch, handles the callback URL, and exposes connect/disconnect controls in the settings shell
- Advanced custom OAuth mode now validates whether a custom native client ID matches the callback scheme compiled into this build and blocks unsupported runtime swaps with a clear explanation
- unit, integration, macOS smoke, iPhone smoke, and iPad smoke validation all passed after the auth wiring landed

## Context and Orientation

Relevant files:

- `.env`
- `client.apps.googleusercontent.com.plist`
- `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj`
- `Calendar Busy Sync/Calendar Busy Sync/Calendar_Busy_SyncApp.swift`
- `Calendar Busy Sync/Calendar Busy Sync/ContentView.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppModel.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AppSettings.swift`
- `Calendar Busy Sync/Calendar Busy Sync/App/Shared/AuditTrail.swift`
- `Calendar Busy Sync/Calendar Busy SyncTests/Calendar_Busy_SyncTests.swift`
- `Calendar Busy Sync/Calendar Busy SyncUITests/Calendar_Busy_SyncUITests.swift`
- `README.md`
- `ARCHITECTURE.md`
- `docs/product-specs/calendar-sync.md`
- `docs/debug-contracts.md`
- `.agents/DOCUMENTATION.md`

External references that shaped this plan:

- Google Sign-In for iOS/macOS setup: `https://developers.google.com/identity/sign-in/ios/start-integrating`
- Google Sign-In integration flow: `https://developers.google.com/identity/sign-in/ios/sign-in`
- Google backend/offline auth notes: `https://developers.google.com/identity/sign-in/ios/offline-access`

## Plan of Work

1. Convert the app target from generated plist settings to a source-controlled project-root `Info.plist` that contains the default Google client ID and reversed callback URL scheme from the bundled Google client plist.
2. Add the `GoogleSignIn-iOS` Swift package plus any required macOS keychain entitlement wiring, then create a small provider-side auth layer that resolves effective OAuth configuration from the default app or the Advanced override.
3. Extend `AppModel` so it owns Google auth state, restore/connect/disconnect actions, explicit validation for unsupported custom-client configurations, redacted user-facing errors, and audit-trail data for auth events.
4. Update the settings UI to show connection state, connect/disconnect controls, custom OAuth guidance, and clear errors for unsupported custom native client IDs.
5. Update tests, docs, and `.agents/DOCUMENTATION.md`, then run sequential Apple build/test commands and docs/plan validators.

## Concrete Steps

1. Add `Calendar Busy Sync/Info.plist`, `Calendar Busy Sync/Calendar_Busy_Sync.entitlements`, and `Calendar Busy Sync/Calendar Busy Sync/App/Providers/Google/` sources.
2. Patch `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj` to:
   - reference the new `Info.plist`
   - include the Google Sign-In Swift package
   - link the `GoogleSignIn` product into the app target
   - add a macOS entitlements file if needed for keychain credential restore
3. Implement provider types for:
   - loading the default Google client configuration
   - resolving the effective OAuth configuration
   - validating custom-client compatibility against the app's bundled callback scheme
4. Update `AppModel` and `Calendar_Busy_SyncApp.swift` to:
   - restore previous sign-in on launch
   - handle `onOpenURL`
   - run connect/disconnect flows on macOS and iOS
   - surface errors and user-facing auth state
5. Update `ContentView.swift`, accessibility identifiers, and audit-trail generation to reflect the live auth surface.
6. Add or adjust unit/UI tests for configuration validation, auth-surface rendering, the Advanced custom-client warning, and redacted auth-error handling.
7. Update durable docs and the documentation log, then run verification commands.

## Validation and Acceptance

Run from `/Users/matthewmoore/Projects/calendar-busy-sync`:

- `python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-19-google-sign-in-wiring.md`
- `./scripts/build --platform macos`
- `./scripts/test-unit`
- `./scripts/test-integration`
- `./scripts/test-ui-macos --smoke`
- `./scripts/test-ui-ios --device both --smoke`
- `python3 scripts/knowledge/check_docs.py`

Acceptance means:

- the project builds after adding Google Sign-In
- the app launches on macOS and iOS with the settings shell intact
- Google restore/connect/disconnect state is visible in the UI
- the default Google OAuth client is compiled into the app configuration
- unsupported custom native client IDs fail with a clear user-facing message instead of silent breakage
- macOS restore is configured with the required keychain access group support

## Idempotence and Recovery

Most changes are additive and reversible. If the package or plist wiring breaks the app build, revert the project settings to the prior app-only state and remove the provider files. If custom OAuth validation proves too strict or too weak, tighten the resolver logic without affecting scenario fixtures or sync-preview behavior.

If sign-in works only on one platform, keep the default integration and platform-guard the broken surface rather than leaving a shared silent failure path.

## Artifacts and Notes

- `GOOGLE_CLIENT_PLIST_PATH` in `.env` currently points at `./client.apps.googleusercontent.com.plist`
- the bundled Google client plist contains:
  - client ID `551260352529-b8bfn0u4c9tnj2lfg99so0njk93j26th.apps.googleusercontent.com`
  - reversed client ID `com.googleusercontent.apps.551260352529-b8bfn0u4c9tnj2lfg99so0njk93j26th`
- no real Google Calendar API calls are in scope for this slice; this is auth wiring only
- sequential `xcodebuild` execution remains required because shared `DerivedData` locking was observed earlier

## Interfaces and Dependencies

- depends on `https://github.com/google/GoogleSignIn-iOS` via Swift Package Manager
- depends on the default client plist matching the app bundle ID `com.matthewpaulmoore.Calendar-Busy-Sync`
- depends on SwiftUI lifecycle callback handling through `onOpenURL`
- depends on macOS signing/entitlements being compatible with Google Sign-In credential storage
- feeds the existing settings and audit-trail shell in `ContentView.swift`
- must preserve harness launch-option behavior and deterministic scenario artifact generation

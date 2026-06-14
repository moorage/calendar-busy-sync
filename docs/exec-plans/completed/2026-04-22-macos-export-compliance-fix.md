# macOS Export Compliance Fix

## Purpose / Big Picture

Clear the current macOS App Store Connect "missing export compliance information" blocker and make future macOS uploads self-describe their encryption posture so the same blocker does not recur.

The immediate remote issue is that the attached macOS build in App Store Connect has no export-compliance value recorded. The local root cause is that the uploaded app bundle does not currently carry `ITSAppUsesNonExemptEncryption`, even though the Xcode project attempts to set that value in build settings.

## Progress

- [x] 2026-04-23T06:22Z inspect the current macOS build state in App Store Connect and confirm the attached build has `usesNonExemptEncryption = null` with no linked app encryption declaration
- [x] 2026-04-23T06:22Z identify the local root cause: the generated app `Info.plist` path does not currently emit `ITSAppUsesNonExemptEncryption`
- [x] 2026-04-23T06:26Z patch the generated plist path so future uploads declare `ITSAppUsesNonExemptEncryption = NO`
- [x] 2026-04-23T06:27Z update the current macOS build in App Store Connect so the attached build reports `usesNonExemptEncryption = false`
- [x] 2026-04-23T06:28Z validate docs/control-plane integrity and capture the resulting App Store Connect state

## Surprises & Discoveries

- 2026-04-23: the Xcode project already sets `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, but the uploaded macOS archive still omits the key because this target uses a generated checked-in `Info.plist` rather than Xcode-generated plist output.
- 2026-04-23: the attached macOS App Store Connect build is otherwise valid and attached to the App Store version; only the export-compliance field is unset.

## Decision Log

- 2026-04-23: treat this as both a remote metadata fix and a local packaging fix, because only clearing the current App Store Connect state would leave the next upload vulnerable to the same blocker.
- 2026-04-23: mark the app as not using non-exempt encryption for App Store Connect purposes, based on the current codebase showing normal platform/network security use and no custom cryptographic implementation.

## Outcomes & Retrospective

Completed:

- `scripts/sync-google-client-config.py` now writes `ITSAppUsesNonExemptEncryption = false` into the generated app `Info.plist`
- `Calendar Busy Sync/Info.plist` now includes the checked-in `ITSAppUsesNonExemptEncryption` key so the repo copy matches generated output
- the attached macOS build `24e4bf9e-9fd9-4641-9200-14c7b759f6bd` now reports `usesNonExemptEncryption = false` in App Store Connect
- the current macOS export-compliance blocker is cleared without requiring a replacement upload

## Context and Orientation

Relevant files and interfaces:

- `scripts/sync-google-client-config.py`
- `Calendar Busy Sync/Info.plist`
- `Calendar Busy Sync/Calendar Busy Sync.xcodeproj/project.pbxproj`
- `scripts/prepare-appstore-macos-submission.py`
- `.agents/DOCUMENTATION.md`

Remote context:

- app id: `6762634278`
- macOS App Store version id: `beaf7da3-88f2-49ea-80f7-a75ae66462af`
- attached macOS build id: `24e4bf9e-9fd9-4641-9200-14c7b759f6bd`

## Plan of Work

1. Patch the generated plist metadata so future app bundles include the export-compliance key.
2. Use the App Store Connect API to set the current macOS build's encryption exemption value.
3. Re-verify plan/docs integrity and record the resolved state.

## Concrete Steps

1. Update the generated plist source so `ITSAppUsesNonExemptEncryption` is written as `NO`.
2. Re-run the repo docs/control-plane validators after updating the active plan and notes.
3. Patch the current macOS build through the App Store Connect API using the existing API helper path.
4. Re-query the macOS build to confirm `usesNonExemptEncryption` is no longer null.

## Validation and Acceptance

Run from repo root:

```bash
python3 scripts/check_execplan.py docs/exec-plans/active/2026-04-22-macos-export-compliance-fix.md
python3 scripts/knowledge/check_docs.py
```

Acceptance means:

- the generated plist path now includes `ITSAppUsesNonExemptEncryption = NO`
- the current attached macOS App Store Connect build no longer reports missing export compliance
- the fix is recorded in the repo control plane for future release work

## Idempotence and Recovery

- rerunning the plist generator should continue to emit the same export-compliance key
- rerunning the App Store Connect build patch should be safe if the build already reports the desired encryption setting
- if App Store Connect rejects the build update, keep the exact API response in the plan and stop rather than guessing at alternate declarations

## Artifacts and Notes

- keep App Store Connect API credentials in `.env` and the local API key file only
- do not create a new upload just to clear this metadata unless the existing build update path fails

## Interfaces and Dependencies

- depends on the repo’s generated plist path remaining the source of truth for uploaded bundle metadata
- depends on App Store Connect API access via `scripts/prepare-appstore-macos-submission.py`

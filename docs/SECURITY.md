# SECURITY.md

This document defines the current security posture.

## Security goals

- protect provider credentials, refresh tokens, and calendar metadata from accidental disclosure
- mirror only occupancy information by default, not sensitive titles, notes, attendees, or conferencing details
- prevent recursive sync loops and unauthorized writes to calendars the user did not explicitly select

## Active trust boundaries

For each trust boundary, list the relevant threats and required controls. This is a summary, not a complete threat model.

### Provider authentication boundary

- inbound data: OAuth credentials, refresh tokens, selected account identity
- core threats: token leakage, over-broad scopes, stale-account reuse
- required controls:
  - request the narrowest provider scopes that still permit reading source busy state and writing mirrored holds
  - store tokens only in platform-appropriate secure storage
  - revoke or discard cached credentials when an account is disconnected

### Provider event payload boundary

- inbound data: provider-specific events, availability flags, organizer metadata, calendar identifiers
- core threats: inconsistent availability semantics, malformed payloads, accidental private data propagation
- required controls:
  - parse provider payloads into typed internal models at adapter boundaries
  - map provider availability into explicit internal busy-state enums
  - default mirrored writes to opaque busy blocks unless a product spec explicitly permits more detail

### Mirror write boundary

- outbound data: busy hold creation requests to selected destination calendars
- core threats: recursive writes, duplicate holds, writing to the wrong calendar
- required controls:
  - track mirror provenance so mirrored events are never re-read as source events
  - require explicit user-selected destination calendars
  - attach deterministic sync identifiers to mirrored writes for idempotent updates and deletes

## Secrets and credentials

- provider tokens and private key material must never be committed
- local `.env` files may hold development-only secrets, but production credentials are out of scope for this repo
- checked-in fixtures under `Fixtures/` must be synthetic and must not contain real account identifiers or event bodies

## Security review triggers

- new provider integration
- scope changes for an existing provider
- changes to mirrored event contents
- background sync or push-based write flows
- any new storage of tokens, calendar IDs, or user-linked account state

## Tests and validation

Security-relevant changes should include:

- malformed payload tests
- permission-denied tests
- recursive-mirror regression tests
- cross-account destination-selection tests
- smoke verification of the selected-calendar write boundary

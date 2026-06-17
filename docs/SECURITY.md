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

### Static booking page boundary

- outbound data: public page copy, appointment metadata, theme values, public encryption key, signed open-slot tokens
- core threats: accidentally publishing private calendar identifiers, provider tokens, raw busy intervals, or private keys
- required controls:
  - generate static artifacts from an allowlisted public data model
  - run public artifact scans before publishing
  - keep Markdown config free of secret-looking values and calendar account emails
  - encrypt visitor requests in the browser before any network submission

### Encrypted request inbox boundary

- inbound data: encrypted booking request envelopes and generic abuse-control metadata
- core threats: relay becoming a calendar backend, request flooding, origin abuse, plaintext logging
- required controls:
  - expose only create, list, delete, and health endpoints
  - require CORS allowlisting for public writes
  - require an admin token for imports and deletes
  - cap payload size, pending count, and request rate
  - avoid request-body logging
  - keep provider credentials, calendar IDs, and plaintext visitor details out of relay storage

## Secrets and credentials

- provider tokens and private key material must never be committed
- app-owned Google and Booking secrets stay in a device-local Keychain vault that routine sync paths can read without repeated local-auth prompts
- local `.env` files may hold development-only secrets, but production credentials are out of scope for this repo
- checked-in fixtures under `Fixtures/` must be synthetic and must not contain real account identifiers or event bodies

## Security review triggers

- new provider integration
- scope changes for an existing provider
- changes to mirrored event contents
- background sync or push-based write flows
- any new storage of tokens, calendar IDs, or user-linked account state
- changes to booking-page public artifacts, signed slot tokens, encrypted request envelopes, or relay endpoint behavior

## Tests and validation

Security-relevant changes should include:

- malformed payload tests
- permission-denied tests
- recursive-mirror regression tests
- cross-account destination-selection tests
- smoke verification of the selected-calendar write boundary

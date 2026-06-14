# Cloudflare encrypted request inbox

This Worker is a blind inbox for Calendar Busy Sync booking requests. It stores encrypted request envelopes only. It has no calendar credentials, no provider tokens, no calendar IDs, and no plaintext visitor details.

Deploy:

1. Create a Workers KV namespace.
2. Put the namespace IDs in `wrangler.toml`.
3. Set `ALLOWED_ORIGIN` to your GitHub Pages origin, such as `https://owner.github.io`.
4. Set `INBOX_ADMIN_TOKEN` with `wrangler secret put INBOX_ADMIN_TOKEN`.
5. Optionally set `TURNSTILE_SECRET_KEY` with `wrangler secret put TURNSTILE_SECRET_KEY`.
6. Run `npx wrangler deploy`.
7. Copy the Worker URL into Calendar Busy Sync as the `Inbox URL`.

Abuse controls:

- 16 KB request size cap
- per-IP rate limit
- per-inbox rate limit
- max pending requests per inbox
- short retention through KV expiration
- optional Turnstile verification
- CORS allowlist for one GitHub Pages origin
- no request-body logging

API:

- `POST /v1/inboxes/:inboxId/requests`
- `GET /v1/inboxes/:inboxId/requests?cursor=...`
- `DELETE /v1/inboxes/:inboxId/requests/:requestId`
- `GET /healthz`

`GET /healthz` returns non-secret setup evidence:

- `ok`
- `allowedOrigin`
- `storage`

Calendar Busy Sync compares `allowedOrigin` with the configured public booking page origin before showing the inbox as ready.

Deploy button:

```text
https://deploy.workers.cloudflare.com/?url=https://github.com/OWNER/REPO/tree/main/templates/booking-relay/cloudflare
```

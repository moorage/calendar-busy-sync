# Cloudflare encrypted request inbox

Cloudflare Workers is the recommended encrypted inbox target for the first release.

The Worker receives encrypted envelopes only. It never sees calendars, provider credentials, calendar IDs, event IDs, or plaintext visitor answers.

## Deploy

1. Open `templates/booking-relay/cloudflare/`.
2. Create a Workers KV namespace.
3. Put the KV namespace IDs in `wrangler.toml`.
4. Set `ALLOWED_ORIGIN` to your GitHub Pages origin, for example `https://owner.github.io`.
5. Set the admin token:

```bash
npx wrangler secret put INBOX_ADMIN_TOKEN
```

6. Optionally set Turnstile:

```bash
npx wrangler secret put TURNSTILE_SECRET_KEY
```

7. Deploy:

```bash
npx wrangler deploy
```

8. Paste the Worker URL into Calendar Busy Sync as `Inbox URL`.

## Abuse controls

The template includes:

- 16 KB payload cap
- per-IP rate limit
- per-inbox rate limit
- max pending requests per inbox
- KV retention expiry
- optional Turnstile verification
- CORS allowlist for one GitHub Pages origin
- admin-token protection for import and delete
- no request-body logging

## Rotate

Rotate `INBOX_ADMIN_TOKEN` if it is shared, logged, or no longer trusted. After rotation, paste the new admin token into the native app when the import workflow is enabled.

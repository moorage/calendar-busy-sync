# Vercel encrypted request inbox

This Vercel template implements the same blind inbox API as the Cloudflare Worker. It stores encrypted request envelopes in Vercel Blob. It has no calendar credentials, no provider tokens, no calendar IDs, and no plaintext visitor details.

Deploy from Calendar Busy Sync:

1. Create or choose a Vercel project for the inbox.
2. Add Vercel Blob storage to the project. Use a public Blob store because the Blob SDK write path requires public object access; the objects contain encrypted envelopes only.
3. Create a Vercel account token at `https://vercel.com/account/settings/tokens`.
4. In Calendar Busy Sync, choose `Vercel inbox`, enter the token, the project ID or project name, and the optional team ID or slug.
5. Run `Deploy Vercel inbox`. The app generates and stores `INBOX_ADMIN_TOKEN`, upserts the relay environment variables, deploys this template, saves the deployment URL, and checks `/healthz`.

After deploy, `GET /healthz` returns non-secret setup evidence:

- `ok`
- `allowedOrigin`
- `storage`
- `storageReady`

Calendar Busy Sync compares `allowedOrigin` with the configured public booking page origin before showing the inbox as ready. `/healthz` returns 503 until the Vercel project has `BLOB_READ_WRITE_TOKEN`.

Vercel limitations:

- This template enforces payload size, max pending requests, CORS allowlisting, admin-token reads, and delete-after-import.
- Vercel Blob object URLs may be readable by anyone who learns a blob URL, so the relay must store only encrypted envelopes and never plaintext visitor details.
- Strong per-IP rate limiting should be added through Vercel Firewall, an upstream WAF, or a small external rate-limit store.
- Expiry cleanup depends on the native app deleting imported or expired requests; add a scheduled cleanup job if you expect high volume.

Deploy button:

```text
https://vercel.com/new/clone?repository-url=https://github.com/OWNER/REPO/tree/main/templates/booking-relay/vercel&env=ALLOWED_ORIGIN,INBOX_ADMIN_TOKEN,MAX_PENDING_REQUESTS
```

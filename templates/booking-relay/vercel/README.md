# Vercel encrypted request inbox

This Vercel template implements the same blind inbox API as the Cloudflare Worker. It stores encrypted request envelopes in Vercel Blob. It has no calendar credentials, no provider tokens, no calendar IDs, and no plaintext visitor details.

Deploy:

1. Create a Vercel project from this folder.
2. Add Vercel Blob storage to the project. Use a public Blob store because the Blob SDK write path requires public object access; the objects contain encrypted envelopes only.
3. Set `ALLOWED_ORIGIN` to your GitHub Pages origin, such as `https://owner.github.io`.
4. Set `INBOX_ADMIN_TOKEN` to a long random value.
5. Confirm the Blob integration added `BLOB_READ_WRITE_TOKEN`.
6. Optionally set `MAX_PENDING_REQUESTS`.
7. Deploy and copy the deployment URL into Calendar Busy Sync as the `Inbox URL`.

After deploy, `GET /healthz` returns non-secret setup evidence:

- `ok`
- `allowedOrigin`
- `storage`

Calendar Busy Sync compares `allowedOrigin` with the configured public booking page origin before showing the inbox as ready.

Vercel limitations:

- This template enforces payload size, max pending requests, CORS allowlisting, admin-token reads, and delete-after-import.
- Vercel Blob object URLs may be readable by anyone who learns a blob URL, so the relay must store only encrypted envelopes and never plaintext visitor details.
- Strong per-IP rate limiting should be added through Vercel Firewall, an upstream WAF, or a small external rate-limit store.
- Expiry cleanup depends on the native app deleting imported or expired requests; add a scheduled cleanup job if you expect high volume.

Deploy button:

```text
https://vercel.com/new/clone?repository-url=https://github.com/OWNER/REPO/tree/main/templates/booking-relay/vercel&env=ALLOWED_ORIGIN,INBOX_ADMIN_TOKEN,MAX_PENDING_REQUESTS
```

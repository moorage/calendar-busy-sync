# Vercel encrypted request inbox

Vercel is the alternate encrypted inbox target. Use it if you already prefer Vercel for small web services.

The Vercel template receives encrypted envelopes only. It never receives calendars, provider credentials, calendar IDs, event IDs, or plaintext visitor answers.

## Deploy

1. Create or choose a Vercel project for the inbox.
2. Add Vercel Blob storage to that project. Use a public Blob store; the relay stores encrypted envelopes only, and the admin API remains the only supported way to list request records.
3. Create a Vercel account token at `https://vercel.com/account/settings/tokens`.
4. In Calendar Busy Sync, choose `Vercel inbox`, enter the Vercel token, the project ID or project name, and the optional team ID or slug when the project belongs to a team.
5. Run `Deploy Vercel inbox`. The app generates the inbox admin token, stores it locally, sets the relay environment variables, deploys this template, saves the deployment URL, and checks `/healthz`.

`GET /healthz` returns 503 until `BLOB_READ_WRITE_TOKEN` is available. That lets Calendar Busy Sync detect a Vercel project that was deployed before Blob storage was attached.

## Limits

The template includes payload-size checks, CORS allowlisting, max pending request checks, admin-token reads, and delete-after-import. Strong per-IP throttling should be added through Vercel Firewall, an upstream WAF, or a small external rate-limit store.

Vercel Blob object URLs can be public when using the SDK write mode required by this template. This is acceptable only because the booking page encrypts visitor details before upload and the relay stores no calendar data, provider credentials, or plaintext request details.

If you expect high volume, add a scheduled cleanup job for expired requests.

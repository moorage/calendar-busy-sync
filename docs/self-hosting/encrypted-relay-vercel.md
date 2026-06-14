# Vercel encrypted request inbox

Vercel is the alternate encrypted inbox target. Use it if you already prefer Vercel for small web services.

The Vercel template receives encrypted envelopes only. It never receives calendars, provider credentials, calendar IDs, event IDs, or plaintext visitor answers.

## Deploy

1. Open `templates/booking-relay/vercel/`.
2. Create a Vercel project from the folder.
3. Add Vercel Blob storage. Use a public Blob store; the relay stores encrypted envelopes only, and the admin API remains the only supported way to list request records.
4. Set environment variables:

```text
ALLOWED_ORIGIN=https://owner.github.io
INBOX_ADMIN_TOKEN=<long random value>
BLOB_READ_WRITE_TOKEN=<created by Vercel Blob>
MAX_PENDING_REQUESTS=100
```

5. Deploy the project.
6. Paste the deployment URL into Calendar Busy Sync as `Inbox URL`.

## Limits

The template includes payload-size checks, CORS allowlisting, max pending request checks, admin-token reads, and delete-after-import. Strong per-IP throttling should be added through Vercel Firewall, an upstream WAF, or a small external rate-limit store.

Vercel Blob object URLs can be public when using the SDK write mode required by this template. This is acceptable only because the booking page encrypts visitor details before upload and the relay stores no calendar data, provider credentials, or plaintext request details.

If you expect high volume, add a scheduled cleanup job for expired requests.

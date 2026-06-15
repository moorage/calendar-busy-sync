# GitHub Pages booking site

Use this guide to host the public booking page in your own GitHub repository.

## Create the repository

1. Create an empty repository for the booking page, for example `booking`.
2. Keep it public if you want GitHub Pages on the free GitHub plan.
3. Enable GitHub Pages from the repository settings.
4. Configure GitHub Pages to serve the repository root on the branch you publish, usually `main` and `/`.

## Create the deploy key

In the native app Publish workspace:

1. Enter the GitHub repository, for example `owner/booking`.
2. Click `Generate deploy key`.
3. Click `Copy public key`.
4. In GitHub, open the repository's deploy-key settings.
5. Add the copied public key as a deploy key and enable `Allow write access`.
6. Return to the app and click `Verify deploy key`.

The app stores the private key in secure storage and never asks for a personal access token. Deploy keys are repository-specific, so do not reuse the generated public key on another repository.

## Build the local artifact

Run:

```bash
./scripts/build-booking-site \
  --output artifacts/booking-site \
  --inbox-url https://example.workers.dev \
  --inbox-id your-inbox-id \
  --share-id intro-call
```

Then validate:

```bash
./scripts/test-booking-site
```

Appointment type Markdown supports per-type weekly hours:

```yaml
weekly_hours: mon=09:00-16:30;tue=09:00-16:30;wed=09:00-16:30;thu=09:00-16:30;fri=closed
```

## Publish

The native app can generate the static page files, open the local page-file folder in Finder, and publish those files to the repository root over Git SSH with the repository deploy key. Repository, branch, public deploy-key metadata, and public page URL settings are stored locally. Publishing uses the app's bundled Git/SSH publishing stack, not the user's system Git or Xcode Command Line Tools. Publishing stops if the repository root already contains files that are not part of the generated booking page.

Manual publishing is still supported. Publish the generated page-file folder contents to the GitHub Pages repository root using your normal Git workflow.

The native app UI uses the copy:

- `GitHub repository`
- `Generate deploy key`
- `Copy public key`
- `Verify deploy key`
- `Booking page URL`
- `Appointment type`
- `Open booking page`
- `Copy booking link`
- `Refresh page files`
- `Publish page`

Appointment-specific share links use the public page URL plus an `appointment` query parameter, for example `https://owner.github.io/booking/?appointment=intro-call`. The static page accepts either the appointment slug or the appointment ID.

The deploy-key private key belongs to this device and should be stored only in Keychain. The copied public key is safe to paste into GitHub.

## Rotate or revoke

Rotate the GitHub deploy key if:

- you copied or moved the private key outside this device
- the repository moved
- you no longer want the app to publish

Remove the old deploy key in GitHub, generate a new deploy key in the app, add the new public key with write access, verify, then publish.

# AI customization for booking pages

The booking template is intentionally ordinary: Markdown, CSS variables, one HTML file, and a small browser script. In the Mac app, open `Booking` -> `Public Page` -> `Open template folder` to reveal the user-editable copy. The app seeds that folder from the bundled template once and uses it as the source for generated page files.

Safe prompts for Codex CLI or Claude Code CLI:

- Change the visual style without changing encryption, request, or availability code.
- Add a new appointment type by editing only Markdown.
- Set weekly hours by editing an appointment type's `weekly_hours` field, for example `mon=09:00-16:30;tue=09:00-16:30;fri=closed`.
- Change copy and colors while preserving the public artifact schema.
- Explain what files are safe to edit and what files should not be touched.

Safe files inside the app's template folder:

- `content/profile.md`
- `content/appointment-types/*.md`
- `content/default-copy.json`
- `assets/styles.css`

Protected generated/protocol files:

- `assets/app.js`
- `public/site-config.json`
- `public/availability/*.json`

The checked-in `templates/booking-site/` directory is the developer seed template. End users should use the app-opened Application Support template folder instead. `Generate page files` copies the editable template into the generated page-files folder, then rewrites generated JSON artifacts before preview or publish.

Before publishing from the Mac app, use `Run safety check` in the Public Page workspace. Developers working from a source checkout can also run:

```bash
./scripts/test-booking-site
```

The test checks that encryption still happens before network submission and that no third-party runtime scripts were added.

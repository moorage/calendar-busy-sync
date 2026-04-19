---
name: record-feature-screencast
description: Record or update a screencast for a new or materially changed user-visible workflow using the repo's ffmpeg-based capture helper when the environment supports it.
---

Use when:
- a new feature or materially changed workflow needs visible acceptance evidence
- the user explicitly asks to record a demo
- the workflow can be shown through the dashboard, local browser flow, or a scripted harness

Default environment:
- `HARNESS_CAPTURE_WITH_FFMPEG=1`
- `HARNESS_CAPTURE_AUDIO_FORMAT=pulse`
- `HARNESS_CAPTURE_AUDIO_INPUT=auto_null.monitor`
- `HARNESS_CAPTURE_DISPLAY=:99.0`

Preferred commands:
- `npm run capture:screencast -- --output artifacts/screencasts/<feature-name>.mp4`
- `npm run capture:screencast:run -- --output artifacts/screencasts/<feature-name>.mp4 -- <workflow-command> [args...]`

Workflow:
1. choose a clear output path under `artifacts/screencasts/`
2. prefer a deterministic scripted workflow when one exists
3. fail early if `ffmpeg`, the PulseAudio monitor input, or the X display is missing
4. verify the output file exists and is non-empty
5. reference the screencast path in the relevant ExecPlan or acceptance notes

If capture fails:
- record the exact failure reason
- do not silently skip the screencast expectation

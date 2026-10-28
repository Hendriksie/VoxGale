# Ideas — the VoxGale parking lot

Raw ideas and observations that are not (yet) OpenSpec proposals. When an
idea matures, promote it: create a proposal in `openspec/changes/` (see
[CONTRIBUTING.md](../CONTRIBUTING.md)) and mark or remove it here. The
historical v1 plan lives at [project-plan.md](project-plan.md).

## From the v1 project plan (§9, historical)

- **Mistral agent integration** — after a session, let the user send the
  transcript to a Mistral agent they've configured (summarize, extract
  action items, file notes). Keep the data model export-friendly so this is
  a drop-in feature.
- **Automatic speaker naming** — batch diarization yields "Speaker 1 /
  Speaker 2" segments; let users rename speakers once, store a local
  speaker profile, and map known voices to names in future captures.
  Interim trick: feed known speaker names as context-biasing keyphrases so
  transcription at least spells names correctly.
- **Live translation** — Small Transcribe 3 supports it.
- **Widgets / quick-start tile** — start a session from the home screen.
- **Wear OS companion.**
- **iOS port** — the architecture allows it later; Android first.
- **On-device wake word** to start sessions hands-free.

## Open observations from dogfooding ([friction-list.md](friction-list.md))

- **Session lost when the battery exemption is revoked mid-session** — on
  GrapheneOS, revoking the exemption while the app was backgrounded killed
  the capture service and the session was gone (severity: data lost).
  Candidate follow-up: detect a dead capture service on resume and offer to
  recover or restart the session, or warn when the exemption is revoked
  mid-session.

## Open questions from the Phase-0 spikes (cancelled probes)

- Realtime API limits — max session length, concurrent sessions.
- The 50%-off batch tier — eligibility and how it bills.
- The `speaker_references` wire format — could enable voice enrollment
  later.

## New ideas (2026-10-28, from the maintainer)

- **In-app update check** — check for updates in-app, including a manual
  "check for updates" action in Settings; also explore the possibilities
  of a full in-app updater. Open questions: version source of truth
  (GitHub Releases API), download + install flow (Android's package
  installer always requires user confirmation for sideloaded APKs), full
  vs delta APK, signature verification of the downloaded artifact.
- **Keep the screen on during sessions** — a Settings toggle that
  disables auto screen-off while a live session is recording (the app
  already holds a partial wake lock for the CPU screen-off; this would
  keep the display awake too). Open questions: scope (live sessions only
  vs any screen), battery impact, interaction with the existing
  wake-lock path.

## Add yours

<!-- One idea per bullet: what it is, why it would be good, open questions. -->

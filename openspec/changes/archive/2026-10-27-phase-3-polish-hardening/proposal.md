# Proposal

## Why

Phases 1 and 2 are archived: live mode and file mode + settings work end-to-end. What remains of v1 is exactly the Phase 3 milestone in `project-plan.md` — polish & hardening — and two of its items are already specced but unimplemented: audio focus is a requirement in the `live-transcription` spec since Phase 1, yet no code handles it, and the wake-lock path has a latent gap (the capture service's plugin intends to hold a partial wake lock while the service runs — `allowWakeLock` defaults to true — but the manifest never declares `WAKE_LOCK`, so the lock cannot actually be held). Why now: v1 feature scope is complete, and this hardening is what stands between the app and dogfooding (Phase 4); the plan explicitly defers the empty/error states, audio focus, tests, and battery review to this phase.

## What Changes

- **Empty/error states** (plan item 1): a consistent empty/error-state system across all screens — no API key, microphone permission denied, no network, API errors (authentication, quota, generic), plus empty states (idle live transcript, empty history, idle file mode). One shared error-state component and message taxonomy, with remedy actions where they exist (open settings, grant permission, retry) and sanitized messages that never include the API key.
- **Audio focus handling** (plan item 2): implement the existing `live-transcription` "Respect audio focus" requirement — pause capture when another application takes audio focus (for example an incoming phone call), resume when focus returns, and indicate the pause in the session UI. Adds `audio_session` as a direct dependency (already in the tree transitively via `just_audio`, so no new package enters the lockfile).
- **Tests** (plan item 3): audit and fill unit-test coverage of the Mistral WebSocket/REST layer with mocked transports (never the live API), and add one integration test of the live flow (start → streaming text → stop → session saved to history) over fake clients.
- **Wake lock + battery review** (plan item 4): declare the `WAKE_LOCK` permission so the capture service's partial wake lock actually engages during screen-off sessions, and make `allowWakeLock: true` explicit in `main.dart`; then measure battery drain over a long screen-off session on a physical device and record the findings. The risk table's "quality vs. battery" chunking setting stays a follow-up decision informed by the measurement, not pre-committed here.
- **App icon** (plan item 4): replace the default Flutter launcher icon with a Mistral-orange icon at every density bucket, plus an adaptive icon (foreground/background) for Android 8+.

## Capabilities

### New Capabilities

- `empty-error-states`: the cross-cutting empty/error-state contract — every screen with a precondition or empty content shows a clear, consistent state (full-screen for blocking failures, banner for non-blocking), with a plain-language message, a remedy action where one exists, and sanitized text that never leaks the API key.
- `app-icon`: the app's launcher icon is the Mistral-orange brand mark at all density buckets, with an adaptive icon on Android 8+.
- `test-coverage`: the Mistral client layer (realtime WebSocket, batch REST, key validation) has unit tests with mocked transports, the live flow has an integration test over fake clients, and no test ever hits the live Mistral API.

### Modified Capabilities

- `live-transcription`: ADD a wake-lock requirement — the device is kept awake (partial wake lock) for the entire time the capture foreground service runs, and no wake lock is held when no session is active. The existing "Respect audio focus" requirement is unchanged; this change closes its implementation gap.

## Impact

- **New code**: a shared error-state widget set in `lib/app/`; an audio-focus seam (platform-channel boundary, per the project's inject-a-seam rule) with wiring in `lib/session/` (pause/resume capture on focus loss/gain); the live-flow integration test under `test/`; icon assets under `android/app/src/main/res/`.
- **Changed code**: `lib/app/live_session_screen.dart`, `file_transcription_screen.dart`, `history_screen.dart`, `settings_screen.dart` (adopt the shared empty/error states); `lib/session/capture_service.dart` / `capture_task_handler.dart` (audio-focus pause/resume); `lib/main.dart` (explicit `allowWakeLock: true`); `android/app/src/main/AndroidManifest.xml` (`WAKE_LOCK` permission); `pubspec.yaml` (`audio_session` promoted to direct).
- **New dependencies** (one-line justification each):
  - `audio_session` — audio-focus management so capture pauses when another app takes focus; already present transitively via `just_audio`, so this promotion adds no new package to the lockfile.
- **No new Mistral surface, no storage schema change, no released users** — nothing to migrate.
- **Testing**: unit tests mock the Mistral layer and platform channels (mocktail) and never hit the live API; the integration test drives the live flow over fake clients; production implementations of new injected seams get direct test coverage (Phase-1 lesson).
- **Mic/foreground-service rule triggered**: audio focus and the wake lock touch the capture path, so `tasks.md` includes a physical-device smoke test (emulators lie about background capture and audio focus).
- **Assumptions**: one change covers all of Phase 3 (Phase-1/2 precedent); the battery measurement's outcome (a "quality vs. battery" chunking setting or not) is a follow-up decision recorded after the measurement; the icon is a simple orange glyph (microphone/waveform mark) produced as PNG assets, since no designer assets exist.

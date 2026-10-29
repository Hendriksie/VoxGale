# Proposal

## Why

During a live session the screen turning off is fine for capture — the
foreground service's partial wake lock keeps the CPU streaming — but users
who read the live transcript while it runs (e.g. taking notes beside the app)
keep having to tap the screen to keep it awake. The parking-lot idea "Keep
the screen on during sessions" (`docs/ideas.md`, 2026-10-28) captures this.
This change promotes it: an opt-in Settings toggle that keeps the display on
for the duration of a live session.

## What Changes

- New persisted preference **"Keep screen on during sessions"** (default
  off), shown as a switch in the settings screen's Transcription preferences
  section and stored in the Drift `preferences` row (schemaVersion 3 → 4).
- When the preference is on, the app holds a **screen wake lock** (Android
  `FLAG_KEEP_SCREEN_ON` via `wakelock_plus`) for the entire live session —
  from session start (while active, including paused) until the session ends
  (stop, error, or teardown) — so the display does not auto-lock while a live
  session runs. When off (the default), behavior is unchanged: the screen may
  turn off and only the existing partial wake lock is held.
- New platform seam `ScreenWakeGateway` in `lib/session/` (interface +
  `wakelock_plus` implementation, mirroring `AudioFocusGateway`), driven by
  `LiveSessionController` on session lifecycle transitions; tests inject a
  fake, never the platform channel.
- Spec deltas: `settings` (offer + persist the toggle) and
  `live-transcription` (hold/release the screen wake lock per the
  preference).
- Explicitly NOT in this change: keeping the screen on outside live sessions
  (home screen, file transcription, history), any dimming behavior, and any
  change to the partial wake lock / foreground-service path — background
  capture with the screen off keeps working exactly as today.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `settings`: new requirement to offer the keep-screen-on toggle in the
  settings screen and persist it.
- `live-transcription`: new requirement to hold the screen wake lock during a
  live session when the preference is enabled, and release it when the
  session ends; the existing "Keep the device awake while capture is running"
  requirement (partial wake lock) is unchanged.

## Impact

- Code: new `lib/session/screen_wake_gateway.dart` seam; provider wiring in
  `lib/session/session_providers.dart`; enable/disable calls in
  `lib/session/live_session_controller.dart` on session start/end; new field
  in `StoredPreferences` + `lib/storage/preferences_repository.dart` and a
  new `keep_screen_on` column in `lib/storage/app_database.dart`
  (schemaVersion 3 → 4 with an `addColumn` migration; regenerate
  `app_database.g.dart`); `SettingsState`/`SettingsController` gain the
  preference and a setter; `lib/app/settings_screen.dart` gains the switch in
  `_PreferencesSection`.
- Dependencies (new, one-line justification):
  - `wakelock_plus` — `flutter_foreground_task`'s `allowWakeLock` only holds
    the partial (CPU) wake lock inside the foreground service; no existing
    dependency sets `FLAG_KEEP_SCREEN_ON` on the activity window, which is
    what keeping the display on requires.
- Manifest: `WAKE_LOCK` is already declared (the partial wake lock uses it);
  `wakelock_plus` needs no additional permission.
- Tests: unit tests with a fake `ScreenWakeGateway` for the controller
  transitions (enable when a session becomes active and the preference is on,
  keep through pause, release on stop/error/teardown, no-op when off),
  storage round-trip + reopen tests for the new column, settings controller
  and settings-screen widget tests for the switch. No test touches a platform
  channel or the live API.
- Device smoke test: this change touches the wake-lock path, so tasks.md
  carries a physical-device smoke-test step (emulators lie about screen/wake
  behavior); this machine has no device, so the step stays pending user
  verification.
- Docs: `CHANGELOG.md` gains an `## [Unreleased]` Added entry;
  `docs/ideas.md` marks the idea as promoted by this change.

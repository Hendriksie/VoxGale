# Design

## Context

VoxGale already holds a **partial wake lock** for the whole capture session
(`flutter_foreground_task` `allowWakeLock: true` in `lib/main.dart`), so
streaming survives the screen turning off — the live-transcription spec's
"Keep the device awake while capture is running" requirement covers exactly
that, and this change does not touch it. What is missing is keeping the
**display** on while a live session runs and the app is foregrounded. The
parking-lot idea lives in `docs/ideas.md` (2026-10-28); motivation and scope
are in `proposal.md`, the behavior contract in `specs/settings/spec.md` and
`specs/live-transcription/spec.md`. Conventions to follow: platform channels
behind interfaces in `lib/` with fakes in tests (see
`lib/session/audio_focus_gateway.dart`), Riverpod wiring in
`lib/session/session_providers.dart`, Drift single-row `preferences` table
for user preferences (schemaVersion currently 3), Material 3 settings UI in
`lib/app/settings_screen.dart`.

## Goals / Non-Goals

**Goals:**

- An opt-in, persisted "Keep screen on during sessions" toggle in Settings.
- While the toggle is on, the display stays on for the whole live session
  (active and paused), and the screen wake lock is released when the session
  ends or fails.
- Everything behind a testable seam; no platform channel in tests.

**Non-Goals:**

- Screen-on outside live sessions (home, file transcription, history) — the
  toggle is session-scoped only.
- Any change to the partial wake lock, the foreground service, or
  background capture with the screen off.
- Dimming the screen instead of keeping it at full brightness.
- File transcription sessions.

## Decisions

1. **Mechanism: `wakelock_plus` behind a new `ScreenWakeGateway` seam in
   `lib/session/screen_wake_gateway.dart`.** On Android,
   `WakelockPlus.enable()/disable()` sets/clears `FLAG_KEEP_SCREEN_ON` on the
   activity window — exactly "keep the screen on". It needs no extra manifest
   permission (`WAKE_LOCK` is already declared for the partial wake lock).
   The interface mirrors `AudioFocusGateway`: `Future<void> setScreenOn(bool
   on)` (idempotent), production impl wraps `WakelockPlus.toggle(enable:)`;
   tests inject a fake. Alternatives rejected: a hand-written method channel
   in `MainActivity` (the repo convention is plugin-plus-interface seams, and a
   bespoke channel would need its own Kotlin for no gain);
   `android:keepScreenOn="true"` in the manifest (static for the whole
   activity — not session-scoped); `flutter_foreground_task` (its
   `allowWakeLock` is the partial CPU wake lock held inside the service
   isolate and cannot set the activity window flag).
2. **Scope: live sessions only, session-scoped.** The screen wake lock is
   enabled when a live session becomes active and held through pauses;
   released on stop, error, or teardown. `FLAG_KEEP_SCREEN_ON` only affects
   the display while the app's window is visible, so backgrounded behavior
   is unchanged automatically — no extra code path needed for "screen off
   while backgrounded still works".
3. **Driver: `LiveSessionController` lifecycle transitions**, reading the
   persisted preference once at session start (`preferencesProvider`). Enable
   after the phase flips to `active` in `_start`; release in `_teardown` (the
   single choke point reached by stop, timeout, and every start-failure path)
   and on the error state. `pause()`/`resume()` do not touch the flag.
   Alternatives rejected: a `ref.listen` on the controller provider from the
   UI layer (implicit side effects, hard to test) — controller-driven matches
   how audio focus is handled (`_startAudioFocusHandling`) and is unit-testable
   with a fake gateway.
4. **Gateway failures are non-fatal.** Setting/clearing the flag is
   best-effort: the controller wraps gateway calls in try/catch and continues
   the session regardless — a screen-wake failure must never fail capture
   (the live-transcription spec's error-surfacing requirement is about
   capture/API errors, not display flags).
5. **Persistence: extend the existing single-row `preferences` Drift table**
   with a nullable `keep_screen_on` bool column (null reads as off — the
   table's existing "null means unset" convention), schemaVersion 3 → 4 with
   `if (from < 4) migrator.addColumn(preferences, preferences.keepScreenOn)`.
   `StoredPreferences` gains `keepScreenOn` (bool, default false), the
   repository round-trips it, `SettingsController` gains
   `setKeepScreenOn(bool)` wired like the existing preference setters.
   Alternatives rejected: a new table (one user preference does not justify
   it) and `shared_preferences` (not a dependency; Drift is the convention).
6. **Settings UI: a `SwitchListTile` in `_PreferencesSection`**
   (`lib/app/settings_screen.dart`), label "Keep screen on during sessions",
   subtitle noting it uses more battery while a session runs, bound to
   `SettingsState.keepScreenOn` and disabled until `state.loaded` — mirroring
   the existing model/language controls.
7. **Default off.** The preference defaults to off so existing users see no
   behavior change; the partial wake lock continues to cover background
   capture exactly as before.

## Risks / Trade-offs

- **[Battery drain while the screen stays on]** → opt-in toggle, default
  off, settings subtitle says it uses more battery; the flag is released
  automatically when the session ends, fails, or the app process dies (the
  window flag dies with the process — nothing to clean up).
- **[Flag leak on an unexpected controller path]** → all exits funnel through
  `_teardown` plus the error state, both of which release the flag; unit
  tests cover stop, timeout, and start-failure paths with a fake gateway.
- **[Schema downgrade]** → Drift refuses to open a v4 database from a v3
  app; downgrades are already an unsupported path (README: install updates
  over the existing copy), same as the update-tracker change.
- **[Emulators lie about screen/wake behavior]** → tasks.md carries a
  physical-device smoke-test step (toggle on, start a session, screen stays
  on; stop, screen times out; toggle off, screen times out during a session
  while capture continues). This machine has no device — the step stays
  pending user verification.
- **[Held through pause]** → deliberate: a paused session is still a running
  session; releasing on pause would surprise users mid-conversation. Can be
  revisited later if dogfooding disagrees.

## Migration Plan

- Drift schemaVersion 3 → 4: add the `keep_screen_on` column via
  `migrator.addColumn` in the existing `onUpgrade`; regenerate
  `app_database.g.dart` with `dart run build_runner build
  --delete-conflicting-outputs`. Additive only, no data migration; existing
  rows read as null → off.
- Rollback: install the previous APK; the only persistent effect is the
  additive column (see the downgrade risk above).

## Open Questions

- Full brightness vs a dimmed keep-screen-on mode — not specified;
  `wakelock_plus` keeps the user's current brightness. A dim mode could be a
  later idea in `docs/ideas.md` without changing these specs' contract.
- The idea's "live sessions only vs any screen" question is settled as
  live-sessions-only (the spec and design both scope it that way); widening
  it later would be a new requirement, not a tweak.

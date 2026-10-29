# Tasks

## 1. Dependency and screen-wake seam

- [x] 1.1 Add `wakelock_plus` to `pubspec.yaml` dependencies with a one-line justification comment (flutter_foreground_task's `allowWakeLock` only holds the partial CPU wake lock in the service; no existing dependency sets `FLAG_KEEP_SCREEN_ON` on the activity window), and verify `flutter pub get` succeeds and `flutter analyze` stays clean.
- [x] 1.2 Create `lib/session/screen_wake_gateway.dart`: the `ScreenWakeGateway` interface (`Future<void> setScreenOn(bool on)`, idempotent) and `WakelockPlusScreenWakeGateway` wrapping `WakelockPlus.toggle(enable:)` (design decisions 1, 4), mirroring `audio_focus_gateway.dart`; add the `screenWakeGatewayProvider` to `lib/session/session_providers.dart`; verify `flutter analyze` is clean.
- [x] 1.3 Add a `FakeScreenWakeGateway` (records calls, configurable failure) under `test/session/` fakes, and verify it compiles and is exercised by the group 3 tests.

## 2. Persisted preference (Drift)

- [x] 2.1 Add a nullable `keepScreenOn` bool column (`keep_screen_on`) to the `Preferences` table in `lib/storage/app_database.dart`, bump `schemaVersion` to 4, add `if (from < 4) await migrator.addColumn(preferences, preferences.keepScreenOn);`, and verify `dart run build_runner build --delete-conflicting-outputs` regenerates `app_database.g.dart` cleanly (design decisions 3, 5).
- [x] 2.2 Extend `StoredPreferences` with `keepScreenOn` (bool, default false when null) in `lib/storage/preferences_repository.dart` — `==`/`hashCode`, load (null → false), save — and verify with `test/storage/preferences_repository_test.dart` on `AppDatabase.memory()` that the field round-trips, defaults to false when unset, and survives a close/reopen on `AppDatabase.file` (design decision 5).

## 3. Controller wiring

- [x] 3.1 In `lib/session/live_session_controller.dart`, read the persisted preference at session start (`preferencesProvider`), enable the screen wake lock via the `ScreenWakeGateway` after the phase flips to `active` in `_start`, and release it in `_teardown` and on the error state; `pause()`/`resume()` do not touch the flag; gateway calls are wrapped so a failure never fails the session (design decisions 2-4). Verify with `test/session/live_session_controller_test.dart` using the fake gateway: enable on active when the preference is on, no call when off, held through pause/resume, released on stop / finalize-timeout / start failure / error, and gateway exceptions swallowed.
- [x] 3.2 Verify the whole `test/session/` suite passes with the new transitions and `flutter analyze` is clean.

## 4. Settings UI and controller

- [x] 4.1 Add `keepScreenOn` to `SettingsState` (with the `_keep` copyWith sentinel pattern) and `setKeepScreenOn(bool)` to `SettingsController`, persisting through `_persistPreferences` like the existing setters (settings spec delta), and verify with `test/session/settings_controller_test.dart`: load applies the persisted value (default false), the setter persists and invalidates `preferencesProvider`.
- [x] 4.2 Add a `SwitchListTile` "Keep screen on during sessions" (subtitle noting it uses more battery during a session) to `_PreferencesSection` in `lib/app/settings_screen.dart`, bound to the state and disabled until `loaded` (design decision 6), and verify with `test/app/settings_screen_test.dart` widget tests: toggle renders with the persisted state, flipping it calls the setter and persists, and it is disabled before load.

## 5. Documentation

- [x] 5.1 Add an `Added` entry under `## [Unreleased]` in `CHANGELOG.md` ("Settings gains a 'Keep screen on during sessions' toggle: while on, the display stays on for the whole live session"), matching the file's Keep a Changelog format, and verify the entry renders in the existing grouping.
- [x] 5.2 Update `docs/ideas.md`: mark the "Keep the screen on during sessions" idea as promoted (change `2026-10-29-keep-screen-on-during-sessions`), and verify the parking-lot flow note at the top of the file is still accurate.

## 6. Verification

- [x] 6.1 Run `flutter analyze` (clean) and the full `flutter test` suite (all green, including the new storage, controller, and widget tests); verify no test touches a platform channel or the live Mistral/GitHub APIs (all seams faked).
- [x] 6.2 Run `openspec validate 2026-10-29-keep-screen-on-during-sessions --strict` and verify the change validates.
- [x] 6.3 Physical-device smoke test (REQUIRED — this change touches the wake-lock path and emulators lie about screen/wake behavior; this machine has no device, so leave pending user verification): with the toggle on, start a live session and verify the screen stays on past the screen timeout; pause/resume and verify it stays on; stop and verify the screen times out normally again; with the toggle off, start a session, let the screen time out, and verify capture continues via the notification and the session saves normally. Record the result before archiving. (Verified: user ran it on a physical device on 2026-10-29 — "I tested it and it works": screen stays on during the session with the toggle on, times out with it off while capture continues.)

## Workflow follow-up

- Archive the change (`openspec archive 2026-10-29-keep-screen-on-during-sessions`) only after tests pass, the device smoke test is verified, and the change is reviewed.
- After archiving, run `openspec validate --specs --strict` to confirm the main `settings` and `live-transcription` specs land cleanly.

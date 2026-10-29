# Tasks

## 1. Dependencies and pinned constants

- [x] 1.1 Add `package_info_plus` and `url_launcher` to `pubspec.yaml` dependencies, each with a one-line comment justifying it (no existing dependency exposes the installed versionName / opens an external URL in the browser), and verify `flutter pub get` succeeds and `flutter analyze` stays clean. (Verified: package_info_plus 10.2.2 + url_launcher 6.3.3 added with justification comments; `flutter pub get` resolved; `flutter analyze` — no issues.)
- [x] 1.2 Create `lib/update/update_config.dart` pinning the GitHub repo slug (`Hendriksie/VoxGale`), the `releases/latest` API path, the `v<semver>` tag scheme, and the 24-hour check throttle, and verify the constants are referenced by the client built in group 3 (design decisions 1-2, 7). (Verified: `lib/update/update_config.dart` created with owner/repo, api host + latest-release path, tag prefix, 24h throttle; referenced by the group 3 client.)

## 2. Persisted update-check state (Drift)

- [ ] 2.1 Add the single-row `update_state` table (`id` `'default'`, `last_check_at_ms` integer nullable, `last_notified_version` text nullable) to `lib/storage/app_database.dart`, bump `schemaVersion` to 3, add the `if (from < 3) createTable(...)` migration, and verify `dart run build_runner build --delete-conflicting-outputs` regenerates `app_database.g.dart` cleanly.
- [ ] 2.2 Add the `UpdateStateRepository` interface and `DriftUpdateStateRepository` in `lib/storage/` (mirroring `PreferencesRepository`), and verify with a new `test/storage/update_state_repository_test.dart` on `AppDatabase.memory()` that the last-check time and last-notified version round-trip and survive a reopen.

## 3. Update client and version comparison

- [ ] 3.1 Create `lib/update/update_check_client.dart`: the `UpdateCheckClient` interface, the `UpdateInfo` model (latest version + release page URL), and the pure semver parse/compare helpers (`v`-prefixed `MAJOR.MINOR.PATCH`, strictly-greater comparison, malformed tags rejected), and verify with unit tests covering newer minor/patch, same version, older tag, and malformed tags.
- [ ] 3.2 Create `lib/update/dio_update_check_client.dart`: the dio implementation of `UpdateCheckClient` against the pinned `releases/latest` endpoint, with explicit connect/receive timeouts and the `baseUrl` set via `BaseOptions` (dio gotchas), returning `null` on any network/HTTP/parse failure, and verify with mocktail tests using a mocked dio (never a live GitHub call) covering the happy path, 404/rate-limit, and malformed JSON.

## 4. Platform seams and test fakes

- [ ] 4.1 Create the `AppVersionReader` and `UrlOpener` interfaces in `lib/update/` with production implementations wrapping `package_info_plus` and `url_launcher`, and verify `flutter analyze` is clean and the app still builds (`flutter build apk --debug` or a debug run).
- [ ] 4.2 Add fakes for both seams plus a fake `UpdateCheckClient` under `test/update/fakes.dart` (mirroring `test/app/fakes.dart`), and verify they compile and are exercised by the group 5-6 tests.

## 5. Controller and Riverpod wiring

- [ ] 5.1 Create `lib/update/update_check_controller.dart`: the `UpdateCheckController` Notifier implementing the spec's behavior — throttled check (only a well-formed response advances the persisted timestamp), semantic comparison, once-per-version notification, silent failure on every error path, and no dialog state while a live session is recording — and verify with unit tests using the fakes: throttle window, retry after failure, malformed tag, already-notified version, and recording-session suppression.
- [ ] 5.2 Create `lib/update/update_providers.dart` wiring the config, repositories, seams, and controller (mirroring `session_providers.dart`, invalidating cached providers on state mutation), and verify with a provider-level test that the controller's state transitions drive the expected provider states.
- [ ] 5.3 Add the manual-check entry point to the controller (`checkNow()`: bypasses the 24-hour throttle, advances the persisted timestamp on a well-formed response, and exposes checking / up-to-date / failed / update-available result states for the UI), and verify with unit tests using the fakes: throttle bypass, timestamp advance, and each result state including failure.

## 6. Update dialog UI

- [ ] 6.1 Create the update dialog widget (Material 3 `AlertDialog`: title "Update available", body naming the available and installed versions, `TextButton` "Later", orange `FilledButton` "Open release") and present it from the home screen when the controller reports an un-notified update, gated on the live session not recording, and verify with a widget test using the fakes that the dialog shows both versions and both actions work.
- [ ] 6.2 Add widget tests for the suppression cases — no dialog when up to date, when the version was already notified, and while a session is recording — and verify the full `test/app/` suite passes with the home screen's new listener in place.
- [ ] 6.3 Add an "Updates" section to `lib/app/settings_screen.dart` (installed version text, "Check for updates" button disabled with a progress indicator while checking, inline up-to-date confirmation, `ErrorBanner` with retry on failure — mirroring the API-key section's patterns), watching the update controller directly, and verify `flutter analyze` is clean.
- [ ] 6.4 Add widget tests for the settings section: dialog shown when a manual check finds a newer version (even if already notified, and while recording), up-to-date confirmation, error banner with retry, and the button disabled while a check runs; verify the settings screen test suite passes.

## 7. Documentation

- [ ] 7.1 Add an `Added` entry under `## [Unreleased]` in `CHANGELOG.md` ("In-app update tracker: the app checks GitHub Releases at most once a day and shows a popup with a button that opens the release page when a newer version is available; Settings gains a manual 'Check for updates' action"), and verify the entry matches the Keep a Changelog format used by the file.
- [ ] 7.2 Add one sentence to `PRIVACY.md` stating that the app checks GitHub Releases for newer versions, unauthenticated, sending no API key or user data, and verify the sentence sits consistently with the existing "what the app does not do" section.
- [ ] 7.3 Update `docs/ideas.md`: mark the "In-app update check" idea as promoted except for the full in-app updater (the tracker and the manual Settings action are implemented by this change; only the updater remains parked), and verify the parking-lot flow note at the top of the file is still accurate.

## 8. Verification

- [ ] 8.1 Run `flutter analyze` (clean) and the full `flutter test` suite (all green, including the new `test/update/` and storage/widget tests), and verify no test hits the live GitHub or Mistral APIs.
- [ ] 8.2 Run `openspec validate 2026-10-29-update-tracker --strict` and verify the change validates.
- [ ] 8.3 Manual run: launch the app on a device/emulator and verify that with the installed version current, no popup appears and the start check is silent; then open Settings, tap "Check for updates", and verify the up-to-date confirmation, and exercise the dialog path by running the controller against a stubbed newer release (the release-notes flow for a real newer release is covered when the next `v*` tag ships). Note: this change does not touch the mic or foreground-service path, so no physical-device smoke test is required beyond this run.

## Workflow follow-up

- Archive the change (`openspec archive 2026-10-29-update-tracker`) only after tests pass and the change is reviewed.
- After archiving, run `openspec validate --specs --strict` to confirm the new main `update-tracker` spec lands cleanly.

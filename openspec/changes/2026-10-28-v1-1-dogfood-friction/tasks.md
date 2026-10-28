# Tasks

## 1. Reactive API-key presence: provider + live controller (design V11-D1, V11-D2)

- [x] 1.1 Add `apiKeyPresentProvider` (FutureProvider<bool>) to `lib/session/session_providers.dart`: derives `key != null && key.isNotEmpty` from `apiKeyProvider` (via `ref.watch(apiKeyProvider.future)` — Riverpod 3's provider-side `.future`); the key value never propagates past the provider. Verify `flutter analyze` is clean. (Verified: analyze — no issues.)
- [x] 1.2 In `LiveSessionController.build()`: `ref.listen(apiKeyPresentProvider, …)`; the listener sets the missing-key error state when no key is saved and no capture is in flight, and clears it (fresh idle state) when a key is saved while that state is showing; ignores presence changes while a capture is in flight. The start-path key check stays. Verify `flutter analyze` is clean. (Verified: analyze — no issues.)
- [x] 1.3 Controller tests (mutation-then-read): with a fake key store overriding `apiKeyStoreProvider`, seed no key → the missing-key state shows without a start attempt; save a key (fake store + invalidate `apiKeyProvider`) → the state clears; remove the key → the state shows again; presence change mid-session is ignored (verified via the provider's recomputed value + a settle delay, asserting the phase stays active). Verify `flutter test test/session/live_session_controller_test.dart` passes. (Verified: 44/44 tests in the file pass, including the 4 new 'key presence tracking' tests.)

## 2. Reactive API-key presence: file transcription controller (design V11-D1)

- [x] 2.1 In `FileTranscriptionController.build()`: replace the one-shot `_loadKeyPresence()` with the same `ref.listen(apiKeyPresentProvider, …)` listener updating `missingApiKey` (the idle view's inline banner then tracks presence: shows when the key is removed, hides when saved). The `pick()`-time key check stays. Verify `flutter analyze` is clean. (Verified: analyze — no issues.)
- [x] 2.2 Controller tests: the banner flag tracks presence both ways (save → hides; remove → shows), mutation-then-read over the fake store. Verify `flutter test test/session/file_transcription_controller_test.dart` passes. (Verified: 17/17 tests in the file pass, including the new tracking test.)

## 3. Battery prompt re-check on foreground resume (design V11-D3)

- [x] 3.1 Add `LiveSessionController.recheckBatteryExemption()`: early-return when no capture is in flight and the prompt flag is unset; otherwise re-read `captureService.isBatteryOptimizationIgnored()` and set `batteryPromptNeeded = !ignored` (dismisses once exempt; keeps/sets within a session context). Verify `flutter analyze` is clean. (Verified: analyze — no issues.)
- [x] 3.2 Convert `LiveSessionScreen` to a `ConsumerStatefulWidget` with a `WidgetsBindingObserver`: on `AppLifecycleState.resumed`, call `controller.recheckBatteryExemption()`; remove the observer on dispose. Verify `flutter analyze` is clean. (Verified: analyze — no issues.)
- [x] 3.3 Tests: a controller test for `recheckBatteryExemption` over a fake capture service (exempt → flag clears; not exempt with the flag set or a session in flight → flag set/stays; no session context → no platform call, flag untouched); a widget test that the screen calls recheck on lifecycle resume (fake controller records the call). Verify `flutter test test/session/live_session_controller_test.dart test/app/live_session_screen_test.dart` passes. (Verified: full suite 353/353 passes — 9 new tests; also fixed test/widget_test.dart to seed a key, since the app-shell test renders the real controller and the new no-key behavior shows the missing-key state.)

## 4. Device smoke + integration checks

- [ ] 4.1 Device smoke (the fixes are UI-state behavior the user hit on device): on the physical device — (a) with no key saved, the live screen shows the missing-key state; save a key in Settings and verify the message disappears on return without a restart; remove the key and verify it returns; (b) start a session without the battery exemption → the banner shows; grant the exemption in the system settings and verify the banner disappears on return; revoke it during a session and verify it reappears on return. Verify each step on device and record the results.
- [ ] 4.2 Run `openspec validate 2026-10-28-v1-1-dogfood-friction --strict`; verify it passes.
- [ ] 4.3 Run `flutter analyze` and the full `flutter test` suite; verify both are clean (no test hits the live API).
- [ ] 4.4 Annotate the two friction-list entries in `docs/friction-list.md` with their disposition (→ this change); verify the file records the triage.

## Workflow follow-up

- Review the change (specs + design + tasks) with the user; archive only after tests pass and the review is done.
- Archive the change, which syncs the delta specs into the main specs; verify the archived result with `openspec validate --strict` and `openspec list`.
- The dogfood window (Phase 4 task 7.2) keeps running — later friction items become follow-up changes (v1.1.x or v1.2).
- Bump the version (pubspec `1.0.0+1` → `1.1.0+2`) and cut the v1.1 release when the user is ready — the release workflow is already proven.

# Tasks

## 1. Dependencies, manifest, and wake-lock option (design P3-D2, P3-D3)

- [x] 1.1 Promote `audio_session` to a direct dependency in `pubspec.yaml` with a one-line justification comment (audio-focus management; already transitive via `just_audio`, so no new package enters the lockfile); verify `flutter pub get` succeeds and `pubspec.lock` gains no new package.
- [x] 1.2 Add `android.permission.WAKE_LOCK` to `android/app/src/main/AndroidManifest.xml` with a comment (the capture service holds a partial wake lock while a session runs); verify a debug build succeeds and the merged manifest under `android/app/build/intermediates/` contains the permission.
- [x] 1.3 Set `allowWakeLock: true` explicitly in `ForegroundTaskOptions` in `lib/main.dart` (documents the intent; survives a plugin default change); verify `flutter analyze` is clean.

## 2. Shared empty/error states (design P3-D1, empty-error-states spec)

- [x] 2.1 Implement `lib/app/error_states.dart`: the full `ErrorStateView` and inline `ErrorBanner` widgets plus the failure-kind → wording/remedy mapping (missing key, mic permission denied, no network, auth, quota, generic); verify with widget tests (each failure kind renders its message and remedy action, in light and dark themes) and a unit test that a failure carrying key-like material renders only the sanitized text.
- [x] 2.2 Adopt the shared states on the live session screen: the idle empty-transcript state, the mic-permission-denied state with a grant-permission action, the no-network state with retry, and the auth/quota distinction in the existing error banner; verify with widget tests for each state, plus a physical-device smoke test of the grant-permission remedy (the native RECORD_AUDIO prompt cannot run in a widget test).
- [x] 2.3 Adopt the shared states on the file transcription screen (missing key, no network, auth/quota errors; the error state keeps the picked file) and align the settings screen's validation errors to the same wording and pattern; verify with widget tests.
- [x] 2.4 Align the history screen's empty state and load-error state with the shared component (empty-history wording distinct from no-search-matches); verify with widget tests.

## 3. Audio focus (design P3-D2, live-transcription spec "Respect audio focus")

- [x] 3.1 Implement the audio-focus seam in `lib/session/`: an `AudioFocusGateway` interface (configure-for-record + a focus-change stream) with an `audio_session`-backed production implementation and a Riverpod provider; verify `flutter analyze` is clean and `flutter pub get` resolves.
- [x] 3.2 Wire focus changes into `LiveSessionController`: configure the session for recording at start; on focus loss send the existing pause command to the capture service, on focus gain send resume; expose a `pausedByAudioFocus` flag; verify with unit tests over a fake gateway (focus loss pauses and keeps the session open, focus gain resumes into the same transcript, no focus events means no commands, dispose releases the audio session).
- [x] 3.3 Surface the audio-focus pause in the live session screen's status row with wording distinct from a user pause; verify with a widget test.

## 4. Tests: coverage audit, gap fill, live-flow integration test (design P3-D4, test-coverage spec)

- [x] 4.1 Audit `test/mistral/` against the test-coverage spec's list (realtime: session setup, audio chunking, event parsing, error mapping, reconnect/buffer; batch: multipart params, diarization params, timeouts, auth/quota/limit error kinds); verify every listed behavior has a named test or a recorded gap.
- [x] 4.2 Fill the realtime client gaps with mocked-transport unit tests (mocktail over the WebSocket channel); verify `flutter test test/mistral/` passes and no test opens a network connection.
- [x] 4.3 Fill the batch client gaps with mocked-HTTP unit tests (request parameters, timeouts, error kinds, no retry of non-retryable failures); verify `flutter test test/mistral/` passes and no test opens a network connection.
- [x] 4.4 Add `test/integration/live_flow_test.dart` as a plain `test()` (the `testWidgets` + real `dart:io` deadlock gotcha): start → fake realtime text deltas → stop → the finalized session appears in history over the in-memory Drift database, plus a mid-session failure case asserting the text so far is preserved with an error state; verify `flutter test test/integration/` passes with no network.

## 5. App icon (design P3-D5, app-icon spec)

- [x] 5.1 Design the orange glyph (a simple microphone/waveform mark on Mistral orange #FF7000, legible at mdpi) and generate the five density PNGs into `android/app/src/main/res/mipmap-*/ic_launcher.png`; verify each file exists at the right size (48/72/96/144/192 px).
- [x] 5.2 Add `mipmap-anydpi-v26/ic_launcher.xml` (adaptive icon: vector foreground drawable + solid orange background) and the foreground drawable under `res/drawable/`; verify the XML is well-formed and references resolve via a successful `flutter build apk --debug`.

## 6. Integration checks

- [ ] 6.1 Run `openspec validate --strict` for this change; verify it passes.
- [ ] 6.2 Run `flutter analyze` and the full `flutter test` suite; verify both are clean (tests mock the Mistral layer and platform channels, never hit the live API).
- [ ] 6.3 Physical-device smoke test (the mic/foreground-service rule triggers — audio focus and the wake lock touch the capture path; emulators lie about background capture and audio focus): on a physical Android device — (a) start a session, receive a phone call mid-session, and verify capture pauses with the audio-focus wording and resumes when the call ends, the transcript continuing in the same session; (b) with the screen off, verify the partial wake lock is held while the session runs (e.g. `dumpsys power`) and released after stop; (c) run a 30+ minute screen-off session and record battery before/after; (d) install the debug APK and verify the orange launcher icon (adaptive icon on API 26+). Verify each step on device and record the results.
- [ ] 6.4 Write the battery-review findings into `battery-review.md` in the change directory (measurement setup, before/after battery, wake-lock verification, and a recommendation for or against a "quality vs. battery" chunking setting); verify the file exists and states a clear recommendation.
- [ ] 6.5 Tick the four Phase 3 milestone items in `project-plan.md`; verify all Phase 3 checkboxes are checked.

## Workflow follow-up

- Review the change (specs + design + tasks) with the user; archive only after tests pass and the review is done.
- Archive the change, which syncs the delta specs into the main specs; verify the archived result with `openspec validate --strict` and `openspec list`.
- Record the battery-measurement outcome as a follow-up decision: build the "quality vs. battery" chunking setting or not.

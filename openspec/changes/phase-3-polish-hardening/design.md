# Design

## Context

Phases 1 and 2 are archived: the app has four production screens (live session, file transcription, history + detail, settings) over controllers in `lib/session/`, capture in a `flutter_foreground_task` foreground service (`lib/session/capture_service.dart` + `capture_task_handler.dart`), all Mistral code behind `lib/mistral/` interfaces, and 29 test files that already mock the Mistral layer. Phase 3 hardens this. Two items are specced-but-unimplemented: the `live-transcription` spec's "Respect audio focus" requirement (no audio-focus code exists anywhere), and the wake lock — the plugin acquires a `PARTIAL_WAKE_LOCK` while the service runs when `allowWakeLock` is true (the default), but `AndroidManifest.xml` never declares `WAKE_LOCK`, so the acquire cannot succeed. Error states exist ad-hoc (missing-key banners on two screens, the live screen's error banner, the history empty state) but there is no shared pattern and no mic-permission, no-network, or quota-specific states. See proposal.md for motivation and the delta specs for requirements.

## Goals / Non-Goals

**Goals:**

- One shared empty/error-state component and message taxonomy adopted by all four screens (empty-error-states spec).
- Audio-focus pause/resume implemented against the existing spec requirement, driven through the existing pause/resume commands.
- The capture service's partial wake lock actually held during sessions (manifest permission + explicit option), verified on device.
- Mistral client layer coverage audited and filled; one live-flow integration test over fake clients (test-coverage spec).
- Mistral-orange launcher icon at all densities plus an adaptive icon (app-icon spec).

**Non-Goals:**

- Spike-harness removal, iOS (including the iOS icon), speaker enrollment, live-diarization UI.
- The "quality vs. battery" chunking setting itself — the battery measurement informs that as a follow-up decision.
- Any redesign of the screens beyond the empty/error states; no changes to the Mistral API surface or the storage schema.

## Decisions

### P3-D1 — One shared error-state component and a failure taxonomy

A new `lib/app/error_states.dart` holds two widgets — a full `ErrorStateView` (icon, plain-language message, optional remedy action button) for blocking failures, and an inline `ErrorBanner` for transient errors — plus a single mapping from failure kinds (`missingKey`, `micPermissionDenied`, `noNetwork`, `auth`, `quota`, `generic`) to wording and remedy actions (open settings, grant permission / open system settings, retry). Controllers map their failures into that taxonomy; screens render the shared widgets and stay dumb, matching the existing screen/controller split.

*Rationale:* the spec's core demand is consistency; one component is the cheapest way to guarantee it, and it gives the widget tests a single target.

*Alternatives considered:* per-screen ad-hoc states — rejected (this is exactly the drift Phase 3 removes); a sealed-class state per screen — rejected (the screens already expose `error` strings and phase enums; a parallel taxonomy would duplicate them).

*Smoke-test refinement:* the live screen's empty transcript state is phase-aware — the "start a session" invitation shows only in the idle and error phases; once a session has run, the area shows a plain "No transcript yet." (mid-session, the invitation wrongly told the user to start a session). `TranscriptView` takes the empty-state message as a parameter for this.

### P3-D2 — Audio focus behind a seam, driven from the UI isolate

`audio_session` (promoted from transitive to direct — it already enters the tree via `just_audio`, so no new package) is wrapped in a small interface (an `AudioFocusGateway`-style seam; it is a platform channel, and platform channels cannot run in unit tests — the project's inject-a-seam rule). The UI isolate configures the session for recording and listens for focus changes: on focus loss it sends the existing pause command to the capture service; on focus gain it sends resume. The session UI indicates the pause through the existing paused phase, with wording that distinguishes "paused — another app is using audio" from a user pause.

*Rationale:* the service already implements pause/resume over its command channel, so audio focus reuses a tested path instead of growing a second one; the UI isolate stays alive while the foreground service runs, so focus callbacks are delivered even when backgrounded.

*Alternatives considered:* handling focus inside the service isolate — rejected (`audio_session` is designed for the main isolate; the service isolate would need its own platform-channel plumbing); ducking instead of pausing — rejected (the spec says pause and resume).

*On-device finding (smoke test, Pixel 9 Pro XL / API 37):* the `record` package requests audio focus itself — its default `AudioInterruptionMode.pause` makes its internal `AudioSessionManager` request focus (`USAGE_MEDIA`) when the recorder starts in the service isolate, about a second after the gateway's `USAGE_VOICE_COMMUNICATION` request. The later request displaced the gateway's and delivered a spurious `AUDIOFOCUS_LOSS`, which paused the session by itself right after start. Fix: the recorder is configured with `audioInterruption: AudioInterruptionMode.none`, so the gateway is the session's only focus owner and its events drive pause/resume through the command channel. Letting record's own interruption policy pause/resume the recorder was rejected — it would need the service isolate to forward recorder state changes to the UI for the paused indication, a second event path for the same behavior.

*Second on-device finding (same smoke test):* a phone call produces a transient focus loss (`AUDIOFOCUS_LOSS_TRANSIENT`) — the gateway pauses and the gain event resumes the session automatically when the call ends (verified: same session, transcript continuing). A media app taking focus can produce a **permanent** loss (`AUDIOFOCUS_LOSS`): `audio_session` then abandons the focus request (its documented Android contract), so no gain event ever arrives and the session stays paused — with the "Paused — another app is using audio" wording and the Resume action — until the user resumes. This is deliberate: re-requesting focus immediately would preempt the other app's audio (voice-communication requests take priority over media), which is exactly the "respect other media apps" behavior the plan asks for. The transient case (calls — the spec's example) auto-resumes; the permanent case waits for the user.

### P3-D3 — Wake lock: fix the permission, make the option explicit, verify on device

No new Dart code for the lock itself: add `android.permission.WAKE_LOCK` to the manifest (a normal, install-time permission — without it the plugin's `acquire()` cannot succeed), and set `allowWakeLock: true` explicitly in `ForegroundTaskOptions` in `lib/main.dart` so the behavior survives a plugin default change and is visible in code review. The battery review is a measurement, not a feature: run a long (30+ min) screen-off session on the physical device, record battery before/after and the wake-lock state (`dumpsys power`), and write the findings into the change's session record; the "quality vs. battery" chunking setting is a follow-up decision informed by that number.

*Rationale:* the plugin already implements the correct behavior (partial wake lock held exactly while the service runs, released on stop — which is also what the new spec requirement demands); the gap is purely the missing permission.

*Alternatives considered:* a separate wake-lock plugin (`wakelock_plus`) — rejected (duplicates what the capture service already does; `wakelock_plus` targets keeping the *screen* on, which is not what screen-off capture needs); doing nothing — rejected (the whole point of the plan item is that screen-off reliability currently rests on the foreground service alone).

### P3-D4 — Coverage audit, gap fill, one live-flow integration test

Audit the existing `test/mistral/` suite against the test-coverage spec's list (session setup, audio chunking, event parsing, error mapping, reconnect/buffer; multipart params, timeouts, auth/quota/limit error kinds) and fill the gaps in place. Add one integration test, `test/integration/live_flow_test.dart`, as a plain `test()` (the `testWidgets` + real `dart:io` deadlock gotcha: file IO belongs in plain `test()`): it drives `LiveSessionController` with fake Mistral clients, the in-memory Drift database, and a fake clock — start → fake realtime text deltas → stop → the finalized session appears in history; a second case fails the stream mid-session and asserts the text so far is preserved with an error state. Widget tests cover the new error/empty states per screen. Production implementations of the new seams (the audio-focus gateway, the shared error-state mapping's production defaults) get direct test coverage, per the Phase-1 lesson.

*Rationale:* the existing suite already mocks the Mistral layer correctly; the spec asks for audited, gap-filled coverage plus one end-to-end flow test, not a new testing architecture.

*Alternatives considered:* a full `integration_test` package run on device — rejected for this item (the live flow over fakes catches regressions in CI; the physical-device smoke test covers what fakes cannot).

### P3-D5 — Icon assets: committed PNGs + adaptive-icon XML, no new tooling

Generate the orange glyph (a simple microphone/waveform mark on the Mistral orange, legible at mdpi) once at the five densities and commit the PNGs under `android/app/src/main/res/mipmap-*/`, plus `mipmap-anydpi-v26/ic_launcher.xml` with a vector foreground drawable and a solid orange background for API 26+. The manifest already points at `@mipmap/ic_launcher`, so no manifest change is needed for the icon itself.

*Rationale:* the assets are produced once and committed; a generator dependency would add tooling for a one-time job.

*Alternatives considered:* `flutter_launcher_icons` as a dev dependency — rejected (a new dependency for a one-time generation step; the justification bar for new dependencies is not met when a one-off script suffices).

## Risks / Trade-offs

- [Audio-focus behavior varies across OEMs and Android versions] → Mitigation: `audio_session` absorbs the platform differences; the physical-device smoke test places a real call during a session and verifies pause + resume.
- [The wake lock increases battery drain by design while a session runs] → Mitigation: held only while the capture service runs (released on stop); the battery-optimization exemption prompt already exists; the Phase-3 measurement quantifies the drain.
- [Error-state taxonomy drifts as new failures appear] → Mitigation: one mapping module; adding a failure kind is a one-line change with a widget test.
- [Icon PNGs are binary assets in git] → Mitigation: small, generated once, reviewed as images; the adaptive-icon XML is the only API 26+ surface.
- [The integration test could rot as the controller grows] → Mitigation: it drives the public controller API over fakes only, so internal refactors do not break it; the full suite runs in CI via `flutter test`.

## Migration Plan

No released users and no data migration: the manifest gains one install-time permission (`WAKE_LOCK`), the pubspec promotes an already-present transitive package to direct, and all other changes are additive code, tests, and assets. Rollback is reverting the change's commits; nothing persists across versions that would need unwinding.

## Open Questions

- The battery-drain number that would justify a "quality vs. battery" chunking setting — answered by the Phase-3 on-device measurement; the setting itself is a follow-up decision, not part of this change.
- The final icon glyph (microphone vs. waveform mark) — a visual choice made during implementation; it does not affect any spec requirement.

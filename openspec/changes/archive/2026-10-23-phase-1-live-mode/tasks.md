# Tasks

## 1. Storage layer (Drift schema + session repository)

- [x] 1.1 Add dependencies — `drift_flutter` (main), `build_runner` + `drift_dev` (dev), `path_provider` promoted to direct main — with the one-line justifications recorded in proposal.md; verify `flutter pub get` succeeds
- [x] 1.2 Define the Drift schema in `lib/storage/app_database.dart` (`sessions` + `segments` tables per design P1-D4) and generate the database code; verify `flutter analyze` reports zero issues on the storage code
- [x] 1.3 Implement `SessionRepository` (interface + Drift implementation): save a finalized session with its segments, load by id, replace the transcript after the diarization pass, delete a session and its audio path; verify repository unit tests against an in-memory Drift database pass

## 2. Mistral client hardening (bounded reconnect buffer)

- [x] 2.1 Cap the reconnect audio buffer in `web_socket_realtime_client.dart` (default 5 minutes, drop-oldest) and add the `BufferedAudioDropped` domain event; verify a unit test simulates a disconnect longer than the cap and asserts the oldest audio is dropped and the event fires
- [x] 2.2 Extend the realtime client tests for the dropped-audio event and keep the existing reconnect/replay/keep-alive tests green; verify the full `test/mistral/` suite passes with the layer mocked (never the live API)

## 3. Production capture service (foreground service, always-on)

- [x] 3.1 Create `lib/session/capture_task_handler.dart` — the production `TaskHandler` promoted from `SpikeTaskHandler`: recorder + WAV written to the app documents dir (`sessions/<id>.wav`, moving `WavFileWriter` from `lib/spike/` to `lib/session/`), realtime session, pause/resume commands, graceful stop, guarded dispose paths; verify `flutter analyze` is clean and a unit test covers the command/event mapping with the Mistral layer mocked
- [x] 3.2 Create `lib/session/capture_service.dart` — the UI-side wrapper: RECORD_AUDIO + POST_NOTIFICATIONS permission checks, battery sanity check (`isIgnoringBatteryOptimizations` + prompt), service start with the polished notification (title, elapsed time via `updateService`, stop `NotificationButton`), command channel, event stream; verify a unit test covers the command/event mapping with the plugin mocked
- [x] 3.3 Add `lib/session/session_models.dart` — `TranscriptTurn`, `SessionState`, and the service-to-UI event serialization; verify a serialization round-trip unit test passes (event to JSON and back)

## 4. Live session controller + post-session pass

- [x] 4.1 Implement `LiveSessionController` (Riverpod notifier): the state machine idle → starting → active ⇄ paused → stopping → finalizing → pass-offered → pass-running → done / pass-failed; turn grouping from the event stream (`TextDelta`/`SpeakerSegment` accumulate into the current turn, `TurnStarted`/`TurnEnded` close blocks); verify controller unit tests with a mocked capture service + repository pass
- [x] 4.2 Implement pause/resume end-to-end (controller → service → recorder) and the paused state in the UI model; verify a controller unit test pauses and resumes and asserts no transcript text is produced while paused
- [x] 4.3 Implement `diarization_pass.dart` — offer with estimated cost (audio duration × configured batch Mini rate), run/skip/retry, replace the provisional transcript with the labelled segments, persist the update, delete the audio after success, preserve the provisional transcript with an error state on failure; verify unit tests with the batch client mocked (never the live API)
- [x] 4.4 Wire finalization: graceful stop → save session + segments + audio path via the repository; verify a controller unit test finalizes a session and asserts the saved record fields (text, labels, timestamps, duration, date, billed usage)

## 5. Live session UI

- [x] 5.1 Build `lib/app/live_session_screen.dart` + transcript widgets: turn-grouped transcript with provisional vs finalized styling, gap markers, subtle connection-status indicator (no spike debug markers), pulsing orange recording indicator, elapsed + estimated cost, actual usage after stop, error states (no key, no permission, API errors) with the key never displayed; verify widget tests cover turn grouping, the provisional/finalized distinction, and the gap marker
- [x] 5.2 Build the session controls: start/stop/pause/resume with correct enablement per state; verify widget tests cover the state-driven enablement
- [x] 5.3 Build the post-session pass offer UI: estimated cost, run/skip actions, pass progress, failure error + retry, actual pass usage; verify widget tests cover the offer/run/skip/failure states
- [x] 5.4 Build the battery-restriction prompt (shown when the app is not exempt, deep-linking to the system battery settings); verify a widget test covers shown/not-shown
- [x] 5.5 Replace the home screen: the live session screen becomes home; the spike links + debug API key entry move behind a debug-only route (design P1-D6); verify the existing widget test still passes and a new widget test covers the debug-route gating

## 6. Physical-device smoke tests (project rule: mic/foreground service — emulators lie about background capture)

- [x] 6.1 PHYSICAL-DEVICE SMOKE TEST: full live session on a real device — start, speak (turn-grouped transcript appears), pause/resume, stop; verify the provisional transcript is finalized and saved, the pass is offered with its estimated cost, running it replaces the transcript with speaker-labelled segments, and the audio file is deleted
- [x] 6.2 PHYSICAL-DEVICE SMOKE TEST: start a session, then turn the screen off for 30+ minutes; verify capture and transcription continue, the notification shows the elapsed time with a stop action, and tapping the notification stop action ends the session gracefully
- [x] 6.3 PHYSICAL-DEVICE SMOKE TEST: toggle airplane mode mid-session; verify the client reconnects, buffered audio is replayed, and the transcript continues without duplicated text (a gap marker appears only if the buffer cap is exceeded)
- [x] 6.4 PHYSICAL-DEVICE SMOKE TEST: with the app not exempt from battery optimization, verify the sanity-check prompt appears and deep-links to the system battery settings; after granting the exemption, verify no prompt appears
- [x] 6.5 PHYSICAL-DEVICE SMOKE TEST: force the post-session pass to fail (airplane mode during the pass); verify the provisional transcript is preserved, the error state explains the failure, and retry succeeds once the network is back

## 7. Integration checks

- [x] 7.1 Run the full unit + widget test suite; verify all tests pass with the Mistral layer and the service channel mocked and no live API calls
- [x] 7.2 Run `flutter analyze`; verify zero issues
- [x] 7.3 Run `flutter build apk --debug`; verify it succeeds (the manifest/service declaration is unchanged)
- [x] 7.4 Run `openspec validate --strict` for this change; verify it passes
- [x] 7.5 Update `project-plan.md`: tick the Phase 1 milestone items once the smoke tests above pass; verify the file reads correctly

## Workflow follow-up

- Review the change (proposal, spec deltas, design, tasks) before archiving.
- Archive the change only after tests pass and the review is complete (project rule).
- Deferred to later changes: the Spike C probes 5.2–5.3 run from the debug-only spike route; spike-harness removal after Phase 2 file mode; history list/search/export UI (Phase 2); audio-focus auto-pause (Phase 3).

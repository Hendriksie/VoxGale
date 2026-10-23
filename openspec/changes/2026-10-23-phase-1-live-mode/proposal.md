# Proposal

## Why

Phase 0 proved the three riskiest paths (realtime streaming, background capture, batch diarization) and deliberately left them as a throwaway spike harness: the app still has no production live mode, no session persistence, and no post-session speaker attribution. Phase 1 of `project-plan.md` turns the proven paths into the actual product — live mode end-to-end. Why now: the foundations change is archived with the spikes verified on a physical device, and the Phase-0 review left explicit production-hardening items (the reconnect audio buffer is unbounded "by design for the spike") that this phase closes.

## What Changes

- **Production live session flow** (plan item 3): the home screen becomes the live session screen — start/stop, a turn-grouped transcript with provisional streaming text visually distinct from finalized text, an unmistakable recording state (pulsing orange indicator; persistent notification while backgrounded), elapsed minutes with estimated cost, and subtle in-UI connection status (reconnects, buffered-audio replay, gaps) instead of spike debug markers.
- **Foreground service promoted to production** (plan item 2): capture and the WebSocket run in the foreground-service isolate for the whole session (no UI-isolate capture path), the notification is polished (app name, elapsed session time, stop action), the POST_NOTIFICATIONS runtime permission is requested up front, and a battery sanity check detects when the app is not exempt from battery optimization and prompts the user to allow unrestricted background activity (OEM battery managers kill the capture service screen-off).
- **Pause/resume** (plan item 2): a user control pauses capture and transcription (the realtime session stays open; the paused period produces no transcript text) and resumes it; the UI shows the paused state.
- **Robust WebSocket lifecycle, production-hardened** (plan item 1): reconnect with identical config, paced buffered replay, and the keep-alive silence feed stay; the audio buffer gets a production cap (oldest audio dropped beyond the cap, surfaced as a visible transcript gap); stop is a graceful end (`input_audio.end`, wait for `transcription.done`); the drop reason (WebSocket close code) captured during the Phase-0 reconnect investigation keeps riding the `Reconnected` event into the UI.
- **Local session persistence** (plan item 3): when a session is finalized, the transcript (text, speaker labels, timestamps, duration, date, billed usage) is saved to the on-device store, and the session audio WAV moves from the temp directory to app-private storage so the post-session pass survives an app restart.
- **Post-session diarization pass, end-to-end** (plan item 4): after stop, the saved session audio is transcribed via the batch API with `diarize=true`; the speaker-labelled result replaces the provisional live transcript; the pass shows its estimated cost and is skippable; on failure the provisional transcript is preserved with an error state and a retry; the session audio is deleted after a successful pass by default.
- **Spike harness demoted, not deleted**: the home screen's spike links move behind a debug-only route; the harness stays because the deferred Spike C probes (API limits, speaker reference clips) still need it. Removing it is a later change (with Phase 2 file mode). The debug-only API key entry moves to the same debug-only route and stays until the Phase 2 settings screen replaces it.

## Capabilities

### New Capabilities

None — all four capabilities already exist in the Phase-0 baseline.

### Modified Capabilities

- `live-transcription`: production session flow — pause/resume, graceful stop, bounded reconnect buffer with visible gaps, polished persistent notification (elapsed time + stop action), battery-restriction sanity check, and in-UI connection status.
- `speaker-attribution`: the post-session diarization pass becomes an end-to-end flow — offered at session end with its estimated cost (run or skip), replaces the provisional transcript on success, preserves it with a retry on failure, deletes the session audio after success by default.
- `transcript-history`: finalized live sessions are persisted locally (text, speaker labels, timestamps, duration, date, billed usage) and the session audio is kept in app-private storage until the diarization pass completes; the history list/search/export UI lands in Phase 2.
- `cost-indicator`: the live-session estimate during the session, actual usage after the session (realtime + post-pass), and the post-pass estimate with a skip option become active; file-transcription cost display lands in Phase 2.

## Impact

- **New code**: `lib/session/` (live session controller + UI state, production foreground-service task handler, pause/resume commands), `lib/storage/` (Drift database + session repository), `lib/app/live_session_screen.dart` with the transcript/turn widgets; `lib/mistral/` hardening (buffer cap + dropped-audio event).
- **Changed code**: `lib/app/home_screen.dart` (becomes the live session entry; spike links and the debug key entry move to a debug-only route), `lib/spike/` (demoted, kept for the deferred Spike C probes). No Android manifest change expected — the microphone-type service and permissions are already declared.
- **New dependencies** (one-line justification each):
  - `drift_flutter` — Flutter bindings for the Drift store chosen in Phase 0: opens the SQLite database in the app's documents directory with the platform glue.
  - `build_runner` (dev) — generates the Drift schema code.
  - `drift_dev` (dev) — Drift's code generator.
  - `path_provider` (promoted transitive → direct) — locates the app documents directory for session audio files.
- **No new Mistral surface**: the realtime and batch clients already implement everything the flow needs; only hardening changes (buffer cap, dropped-audio event) touch `lib/mistral/`.
- **Testing**: unit tests mock the Mistral layer and the service data channel (mocktail) and never hit the live API; the mic/foreground-service behavior gets physical-device smoke tests (emulators lie about background capture — project rule).
- **API key**: Phase 1 keeps the debug-only key entry (moved to the debug-only route); the real settings screen with key validation is Phase 2.

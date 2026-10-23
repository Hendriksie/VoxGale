# Design

## Context

Phase 0 (`2026-10-23-voxtral-v1-foundations`, archived) left: a complete, unit-tested `lib/mistral/` client layer (realtime WebSocket + batch REST behind interfaces, reconnect with paced buffered replay, keep-alive silence feed, exponential backoff, close-code diagnostics); a working Android foreground-service pipeline proven screen-off for 30+ minutes on a Pixel 9 (GrapheneOS); and a throwaway spike harness (`lib/spike/`) wired to a debug-only home screen. The six baseline capability specs in `openspec/specs/` describe v1-target behavior; this change implements the live-session slice of them (see the delta specs for the requirement-level changes).

Hard constraints carried over: all Mistral API code stays in `lib/mistral/` behind interfaces; the API key lives in secure storage only and is injected only into `lib/mistral/` clients; tests mock the Mistral layer and never hit the live API; anything touching mic/foreground service gets a physical-device smoke test in tasks.md.

Verified plugin surface (flutter_foreground_task 11.0.3): `startService(notificationTitle:, notificationText:, notificationButtons:, callback:)` supports a notification stop button (`NotificationButton(id, text)`), `updateService(...)` updates the notification while running, and `isIgnoringBatteryOptimizations` / `requestIgnoreBatteryOptimization()` / `openIgnoreBatteryOptimizationSettings()` cover the battery sanity check. No new plugin dependency is needed for any of these.

## Goals / Non-Goals

**Goals:**
- A production live session flow: start/stop/pause/resume, turn-grouped transcript, unmistakable recording state, graceful stop, and finalized-session persistence.
- Capture owned by the foreground service for the whole session, with a polished notification (elapsed time + stop action) and a battery-restriction sanity check.
- Production-hardened reconnect: bounded audio buffer with visible gaps instead of an unbounded spike buffer.
- The post-session diarization pass wired end-to-end: offered with its estimated cost, skippable, replacing the provisional transcript, with failure/retry and audio deletion.

**Non-Goals:**
- History list/search/export UI, the settings screen (with key validation), file transcription, audio-focus auto-pause, and speaker enrollment UI — those are Phases 2–3 against the same specs.
- Removing the spike harness (it stays behind a debug-only route for the deferred Spike C probes 5.2–5.3).
- Compressed session audio (WAV only, as in Phase 0); iOS.
- Measuring battery drain quantitatively (dropped by user decision in Phase 0; the Phase-1 "battery sanity check" is the battery-optimization exemption check + prompt, not a drain measurement).

## Decisions

### P1-D1 — The foreground service owns capture for the whole session; the UI never captures
The production live mode always runs recorder + WebSocket in the service isolate; the UI sends commands (start/stop/pause/resume) and renders events forwarded over the plugin's data channel. No UI-isolate capture path exists.

*Rationale:* Phase-0 decision D4 — the microphone must be held by the service for background capture to be permitted, and the isolate split is unavoidable with this plugin. Spike B proved the service-isolate pipeline works screen-off for 30+ minutes. Always-on service capture removes the alternative's worst failure mode: handing a live recorder + socket between isolates at backgrounding time.

*Alternative considered:* capture in the UI isolate while foregrounded and hand off to the service on background — rejected; the handoff is a mid-session migration of a live recorder and socket that the spikes never exercised.

### P1-D2 — Pause/resume are commands to the service; the realtime session stays open
Pause stops the recorder and the audio flow; the client's keep-alive silence feed keeps the server session alive; resume restarts the recorder and the transcript continues in place. The paused period produces no transcript text.

*Rationale:* pausing without ending the session preserves turn context and costs no reconnect. Turn detection will close the current turn when the pause begins (the pause is silence) — acceptable and honest; the transcript shows the pause as a turn boundary.

*Alternative considered:* pause = end session, resume = new session with buffered replay — rejected; it burns a reconnect, splits the transcript of record across sessions, and complicates finalization.

*Interpretation recorded:* the plan's Phase-1 "pause/resume" is the user control. Automatic pause on audio-focus loss (phone calls) is Phase 3 per the plan and the `live-transcription` spec's existing "Respect audio focus" requirement; this change does not implement it.

### P1-D3 — Bounded reconnect buffer: cap, drop-oldest, surface a gap
The Phase-0 client buffer is unbounded ("a production session should cap it" — code comment). Phase 1 caps it at 5 minutes of PCM16 (~9.6 MB at 32 KB/s), drops the oldest chunks beyond the cap, and emits a new `BufferedAudioDropped(seconds)` domain event; the UI renders a visible gap marker at the reconnect point. Already-displayed text is never rewritten (deltas are append-only, per Phase-0 D6).

*Rationale:* an unbounded buffer is an OOM waiting to happen on a long outage; a capped buffer with an honest gap marker matches the spec's "never lose or rewrite transcript text that was already displayed" while acknowledging that unrecoverable audio is lost.

*Alternatives considered:* keep unbounded (spike behavior) — rejected, memory risk; compress the buffer — rejected, encoder dependency for a rare path.

### P1-D4 — Session persistence: Drift schema + repository now; history UI in Phase 2
`lib/storage/` holds a Drift database with two tables — `sessions` (id, started-at, duration, billed audio seconds, actual cost, model, language, status provisional/final, audio path) and `segments` (session id, speaker label, text, start/end seconds, order) — behind a `SessionRepository` interface so the UI layer stays storage-agnostic and mockable. Phase 1 writes the finalized session + segments and the audio path; Phase 2 builds list/search/export on the same schema. Session audio moves from the spike's temp-dir WAV to `getApplicationDocumentsDirectory()/sessions/<id>.wav`.

*Rationale:* Drift is the project's chosen local store (config context; Phase-0 dependency justification "transcript history with search"). Saving JSON files in Phase 1 would create a throwaway format and a Phase-2 migration.

*Alternative considered:* JSON files in Phase 1, Drift in Phase 2 — rejected for the above; the schema is small (two tables) and Phase 1's save path is the natural first writer.

*New dependencies:* `drift_flutter` (Flutter bindings for the already-chosen Drift store), `build_runner` + `drift_dev` (dev, schema codegen), `path_provider` promoted transitive → direct (audio directory). Each carries its one-line justification in proposal.md.

### P1-D5 — The post-session pass is orchestrated by the session controller in the UI isolate
Stop flow: graceful end (`input_audio.end`, wait for `transcription.done`) → close the WAV → save the provisional transcript + audio → offer the pass (estimated cost = audio duration × the configured batch Mini rate) → run or skip. Run: one-shot `BatchTranscriptionClient.transcribe(diarize: true, model: Mini)` on the saved WAV in the UI isolate; on success the speaker-labelled segments replace the provisional transcript (persisted), the pass's actual usage is shown, and the audio file is deleted; on failure the provisional transcript is preserved with an error state and a retry that re-reads the saved audio. Skip: provisional transcript stands as the transcript of record and the audio is kept so the pass can still be run later (Phase 2 re-offers it from the history detail view).

*Rationale:* the pass is a one-shot REST call after the session ends — it does not belong in the capture service, and the spec makes the offer/skip a UI concern. Batch Mini is the default because it is the cheapest diarizing model; the Small-vs-Mini preference is a Phase-2 settings concern.

*Alternatives considered:* running the pass inside the service isolate — rejected (the service exists for capture; a one-shot call belongs to the UI layer); deleting audio on skip — rejected (makes skip irreversible and breaks the retry path's data source).

### P1-D6 — Spike harness demoted to a debug-only route, not deleted
The home screen becomes the live session screen. The spike screens and the debug-only API key entry move behind a debug-only route (`kDebugMode` gate), because the deferred Spike C probes (5.2 API limits, 5.3 speaker reference clips in both modes) still need the harness. Removal is a later change, after Phase 2 file mode lands and the probes are done.

*Rationale:* the harness is the only working runner for the deferred probes; deleting it now would silently drop user-approved follow-up work.

*Alternative considered:* delete the harness now — rejected for the above; keep it on the home screen — rejected (spike UI on the production home is confusing).

### P1-D7 — Layer layout for the new code
- `lib/session/` — `live_session_controller.dart` (Riverpod notifier: session state machine idle → starting → active ⇄ paused → stopping → finalizing → pass-offered → pass-running → done/pass-failed), `session_models.dart` (`TranscriptTurn`, `SessionState`), `capture_service.dart` (UI-side wrapper around flutter_foreground_task: start/stop, command channel, event stream), `capture_task_handler.dart` (production `TaskHandler`, promoted from `SpikeTaskHandler`), `diarization_pass.dart` (the pass orchestration).
- `lib/storage/` — `app_database.dart` (Drift), `session_repository.dart` (interface + Drift implementation).
- `lib/app/` — `live_session_screen.dart` + transcript widgets; `home_screen.dart` becomes the live session entry with a debug-only menu.
- `lib/mistral/` — only hardening: buffer cap + `BufferedAudioDropped` event in `web_socket_realtime_client.dart` (and its event parser/test surface).

Turn grouping happens UI-side in the controller: `TextDelta`/`SpeakerSegment` accumulate into the current `TranscriptTurn`; `TurnStarted`/`TurnEnded` close blocks; provisional turns are styled distinctly from the finalized diarized transcript that replaces them.

## Risks / Trade-offs

- **[The service runs even in the foreground]** → the notification is always visible during a session. Mitigation: it carries elapsed time and a stop action, so it is informative, not noise; this matches the spec's "persistent notification" requirement.
- **[The intermittent reconnect storm from Phase 0 is still unexplained]** → bursts every ~3–10 s while transcription continues seamlessly. Mitigation: the drop reason (close code) already rides the `Reconnected` event; the production UI surfaces connection status, so the next occurrence is observable in the product, not only in spike logs. The keep-alive feed and paced replay stay as-is.
- **[Capped buffer loses audio on outages > 5 min]** → the transcript shows a gap marker. Mitigation: honest display per spec; 5 minutes is a generous outage bound for mobile networks.
- **[Skipped passes keep session audio on disk]** (~1.9 MB/min) until Phase 2 adds re-run/delete UI. Mitigation: documented trade-off; Phase 2's history delete removes audio (spec: "removing the transcript and its associated locally stored audio").
- **[OEM battery managers kill the service screen-off even with the exemption prompt]** → some devices need manual "unrestricted battery" (observed on GrapheneOS in Phase 0). Mitigation: the sanity check prompts and deep-links to the system battery settings; the smoke test covers the prompt; a fuller onboarding explainer is a Phase-3 polish item.
- **[Drift codegen adds build_runner to the dev workflow]** → slower builds during development. Mitigation: dev-only dependency; generated code is committed like any other generated artifact.
- **[Batch duration/size limits for Voxtral 3 remain unverified (deferred Spike C 5.2)]** → a very long session might exceed what one pass accepts. Mitigation: chunking fallback already identified in Phase-0 design; the pass failure path preserves the provisional transcript, so nothing is lost.
- **[The realtime session stays open while paused]** → a paused session still holds the socket (keep-alive silence only). Mitigation: pause is a user action with a visible state; stop is the way to end. Server-side session limits are unverified (same deferred probe).

## Migration Plan

Not a data migration — the app has no released users. Code migration: the spike harness stays in place (demoted to a debug route, P1-D6), so nothing is deleted in this change. The only behavioral migration is the session audio location (temp dir → app documents dir); the spike's temp-dir WAV is a debug artifact and is not carried over. The debug-only API key entry moves from the home screen to the debug route; the key itself stays in secure storage, unchanged.

## Open Questions

- **Does the pinned flutter_foreground_task 11.0.3 notification button deliver taps to the service or the UI isolate?** The plugin's `NotificationButton` ids surface through the task's data/event channel; the implementation will route the stop button to the same stop command as the UI's Stop (design is unaffected either way — the smoke test verifies which channel fires and the handler covers both). Safe to answer during implementation.
- **Should the pass re-offer appear in Phase 1 for sessions whose pass was skipped?** No UI surface exists for it until Phase 2 history; recorded as a Phase-2 follow-up rather than a Phase-1 gap.
- **Exact buffer cap value (5 min) and whether it should become a user setting** — default 5 min now; a "quality vs. battery"-style setting is a Phase-3 candidate. Does not change the specs.

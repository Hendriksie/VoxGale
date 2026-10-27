# Proposal

## Why

User-reported while reviewing the Phase 3 build on a physical device: **while a session is paused, the elapsed timer keeps running — in the app's status row and in the persistent notification.** The root cause is a Phase 1 design decision (P1-D2): during a pause the realtime client feeds keep-alive silence (~100 ms of audio every ~750 ms, billed by the API at roughly 13% of the active rate — verified by billing: a 5:50 session whose recorder was paused from 2 s in billed 50 s ≈ the silence fed), and the controller deliberately kept the timer and cost estimate running to reflect that billing. Both halves are wrong for this app: a paused session should cost nothing (BYO-key users pay for every billed second — paying for keep-alive silence is a bill surprise, which the cost-indicator spec exists to prevent), and the clock should represent active capture time (every recorder app stops the clock on pause).

## What Changes

A pause becomes a true stop, end to end:

- **No audio while paused.** The realtime session learns about pauses (`RealtimeSession.setPaused`): while paused it stops the keep-alive silence feed, so no audio is sent and no cost accrues. A disconnect while paused is **not** retried — the server may idle-close a silent session, and reconnecting while paused would loop (close → connect → close). Resuming restarts the feed and reconnects first if the connection was lost; audio captured between resume and reconnect is buffered and replayed by the existing reconnect path.
- **The clock stops while paused.** The elapsed session time freezes in the app's status row and in the persistent notification ("Paused · MM:SS" holds still), and resumes from where it paused. The cost estimate is elapsed × rate, so it accrues only while capturing.
- **Unchanged:** the session stays open across pauses (no reconnect for short pauses, turn context preserved); the transcript continues in the same session on resume; stopping, finalization, and the post-session pass are untouched.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `live-transcription`: the "Pause and resume a live session" requirement changes — while paused, no audio is sent to the transcription API (no cost accrues) and the elapsed session time does not advance in the app or the notification; resuming after a stream that was closed while paused reconnects first and continues the same session.
- `cost-indicator`: the "Show estimated cost during a live session" requirement changes — the elapsed time and the estimate advance only while capture is active.

## Impact

- **Changed code**: `lib/mistral/realtime/realtime_transcription_client.dart` (`RealtimeSession.setPaused`) and `web_socket_realtime_client.dart` (pause state: keep-alive suppression, reconnect deferral, reconnect-on-resume); `lib/session/capture_task_handler.dart` (forward pause/resume to the session; frozen notification elapsed); `lib/session/live_session_controller.dart` (paused-time accumulation in the tick and the finalization duration; estimate accrues only while active).
- **Tests**: client unit tests (no silence while paused; no reconnect loop while paused; reconnect + replay on resume; no reconnect when still connected), controller unit tests (timer and estimate frozen while paused, resume continues, final duration excludes pauses), service unit tests (pause/resume forwarded to the session; frozen notification elapsed). Existing fakes gain the new interface method.
- **No new dependencies, no storage schema change, no migration.** The spec deltas modify two existing requirements; no requirement is removed.
- **Mic/foreground-service rule triggered**: the change touches the capture service and the realtime client — `tasks.md` includes a physical-device smoke test (the device is connected): pause freezes the app timer and the notification, resume continues, and the billed seconds at the end match the active time (proving no silence is billed while paused); a long pause verifies the reconnect-on-resume path.
- **Assumptions**: the server's idle timeout for silent sessions is unknown (the Phase-0 spike observed idle-closes during pauses); the smoke test measures the actual behavior. The keep-alive's protection against recorder-chunk stalls during *active* capture is preserved (it only stops while explicitly paused).

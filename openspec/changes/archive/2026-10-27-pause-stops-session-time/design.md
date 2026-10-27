# Design

## Context

Phase 1's design P1-D2 keeps a paused session's realtime stream alive by feeding keep-alive silence (~100 ms of audio every ~750 ms while no mic audio arrives — billed by the API at roughly 13% of the active rate; confirmed by billing: a 5:50 session whose recorder paused at 2 s billed 50 s ≈ the silence fed). The controller then deliberately kept the elapsed timer and the cost estimate running while paused to reflect that billing. The user reported the running timer as wrong. See proposal.md for motivation and the delta specs for requirements.

## Goals / Non-Goals

**Goals:**

- A pause is a true stop: no audio is sent while paused (no transcription cost accrues), and the elapsed session time freezes in the app and in the persistent notification.
- Resuming continues the same session and transcript; if the stream was closed while paused, it is re-established before audio flows again.
- The cost estimate (elapsed × rate) accrues only while capturing, so it matches the bill.

**Non-Goals:**

- Changing the reconnect/buffer behavior during *active* capture (the keep-alive still protects against recorder-chunk stalls while capturing — it only stops while explicitly paused).
- Changing turn detection, finalization, the post-session pass, or the audio-focus pause semantics (the focus pause goes through the same `pause()` path and gets the same behavior).
- Ending the session on pause (rejected in Phase 1, P1-D2 — unchanged).

## Decisions

### PS-D1 — `RealtimeSession.setPaused(bool)`: no audio, no reconnect while paused

The session interface gains `setPaused(bool)`. While paused, the client stops the keep-alive silence feed (so nothing is sent and nothing is billed) and does **not** retry a disconnect: the server may idle-close a silent session, and the client's existing reconnect loop would then spin (close → connect → close) for the whole pause. A disconnect while paused just marks the session disconnected. On resume, the client restarts the feed and, if disconnected, reconnects via the existing path — audio captured between resume and reconnect is buffered and replayed, so nothing is lost.

*Rationale:* this is the only way to make a pause free without regressing the Phase-0 finding that motivated the keep-alive (idle-closes during pauses). The reconnect-on-resume is seamless for the transcript: nothing was captured during the pause, the buffer replays what was captured after resume, and the turn context was already closed by the pause's silence.

*Alternatives considered:* keeping the silence feed and only freezing the timer — rejected (the pause would still be billed, invisibly, contradicting the estimate and the cost-indicator spec's "never surprised by a bill"); removing the keep-alive entirely without a paused state — rejected (the client would reconnect-loop during pauses, since it always tries to maintain the session).

### PS-D2 — The elapsed session time is active capture time

The controller accumulates paused durations (`pause()` records the pause start, `resume()` accumulates it) and subtracts them in the tick and in the finalization duration, so `elapsedSeconds` — and the estimate derived from it — advance only while the phase is `active`. The service's notification text computes the same active elapsed (a small static helper, unit-tested) so "Paused · MM:SS" holds still. The saved session duration is the active time, matching the billed audio.

*Rationale:* one definition of "elapsed session time" everywhere (app row, notification, history duration), consistent with "the paused period produces no transcript text" — a pause is a hole in the session, not part of it.

*Alternative considered:* showing wall-clock session time alongside an active-time cost — rejected (two clocks on one small status row is confusing; the user's expectation is a single clock that stops on pause).

## Risks / Trade-offs

- [A long pause may reconnect on resume] → Mitigation: the reconnect is the existing, tested path; the user sees at most a brief "Reconnected" chip, and no audio is lost (the pause captured nothing). The turn context resets — but the pause's silence already closed the turn.
- [The server's idle timeout is unknown] → Mitigation: the physical-device smoke test measures it (a long pause, then resume, watching for the reconnect).
- [The reconnect deferral could leak a reconnect loop] → Mitigation: unit tests pin that a disconnect while paused triggers no connection attempts, and that resume triggers exactly one reconnect.
- [The estimate no longer counts keep-alive silence during active-capture stalls] → Mitigation: while capturing, the mic delivers audio continuously, so the feed almost never fires; and if it does, the silence is a fraction of a percent of the session.

## Migration Plan

No data migration and no dependency changes — a pure behavior change over existing code. Rollback is reverting the change's commits.

## Open Questions

None material — the device smoke test answers the one unknown (the server's idle-close behavior during a long pause).

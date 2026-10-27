# Tasks

## 1. Realtime client: setPaused + no audio and no reconnect while paused (design PS-D1)

- [x] 1.1 Add `setPaused(bool paused)` to the `RealtimeSession` interface in `lib/mistral/realtime/realtime_transcription_client.dart` (doc comment: while paused no audio is sent — including no keep-alive silence — so a pause costs nothing; a disconnect while paused is not retried; resuming reconnects if the connection was lost).
- [x] 1.2 Implement it in `WebSocketRealtimeSession` (`lib/mistral/realtime/web_socket_realtime_client.dart`): a `_paused` flag; `setPaused(true)` stops the keep-alive timer; `_handleDisconnect` returns without starting the reconnect loop while `_paused` (after the usual dead-channel cleanup); `setPaused(false)` clears the flag, restarts the keep-alive, and — if disconnected — triggers the existing reconnect path (fire-and-forget); verify `flutter analyze` is clean.
- [x] 1.3 Add unit tests in `test/mistral/realtime_client_test.dart` (mocktail `MockWebSocketChannel` + `RecordingWebSocketSink`, short configurable `keepAliveAfter`/`reconnectDelay`): while paused, no silence chunk is sent even well past the keep-alive threshold; a disconnect while paused triggers no new connection attempts (channel factory call count stays put); resuming while disconnected reconnects and replays the buffered audio; resuming while connected does not reconnect; verify `flutter test test/mistral/` passes.

## 2. Capture service: forward pause/resume; frozen notification elapsed (design PS-D1, PS-D2)

- [x] 2.1 In `lib/session/capture_task_handler.dart`: `_pause()` calls `_session?.setPaused(true)` after pausing the recorder; `_resume()` calls `_session?.setPaused(false)` before resuming the recorder; stub `setPaused` on the `MockRealtimeSession` in `test/session/capture_task_handler_test.dart` and add tests that the pause/resume commands forward it; verify `flutter test test/session/capture_task_handler_test.dart` passes.
- [x] 2.2 Freeze the notification's elapsed time while paused: track `_pausedAt`/`_pausedAccumulated` in the handler; compute the displayed elapsed with a small static helper `activeElapsed({startedAt, now, pausedAccumulated, pausedSince})` (the paused durations are subtracted); `_updateNotification` uses it; add unit tests for the helper (no pause, one pause, a pause in progress, multiple pauses); verify the handler tests pass.

## 3. Controller: active-time clock and estimate (design PS-D2)

- [x] 3.1 In `lib/session/live_session_controller.dart`: accumulate paused durations (`pause()` records `_pausedAt` via the clock, `resume()` accumulates); `_onTick` advances `elapsedSeconds`/`estimatedCost` only while the phase is `active`, subtracting the accumulated paused time (remove the "estimate keeps growing while paused" comment); `_finalize` computes `durationSeconds` the same way (active time); verify `flutter analyze` is clean.
- [x] 3.2 Add unit tests in `test/session/live_session_controller_test.dart` with the fake clock: the timer and estimate freeze while paused and resume from the frozen value; a session with a pause finalizes with a duration that excludes the paused time; verify the controller tests pass.

## 4. Spec deltas and validation

- [x] 4.1 Verify the delta specs exist and match the implementation: `specs/live-transcription/spec.md` (MODIFIED "Pause and resume a live session") and `specs/cost-indicator/spec.md` (MODIFIED "Show estimated cost during a live session"); run `openspec validate pause-stops-session-time --strict`; verify it passes.

## 5. Integration checks

- [x] 5.1 Run `flutter analyze` and the full `flutter test` suite; verify both are clean (tests mock the Mistral layer and platform channels, never hit the live API).
- [x] 5.2 Physical-device smoke test (the mic/foreground-service rule triggers — the capture service and the realtime client change): on the connected physical device, install the rebuilt debug APK — (a) start a session, pause it, and verify the elapsed timer freezes in the app's status row and in the persistent notification ("Paused · MM:SS" holds still over ~20 s); (b) resume and verify the timer continues from the frozen value; (c) stop and verify the billed seconds match the active capture time (no silence billed while paused); (d) pause for 90+ s (past the server's idle close), resume, and verify the transcript continues in the same session (watching for the reconnect chip); verify each step on device and record the results in the change.

Device session results (2026-10-27, Pixel 9 Pro XL / API 37): (a) paused at 0:35 — the app status row held "0:35 est. $0.005 Paused" identical across 15 s, and the notification shade held "Paused · 00:33" identical across 12 s (the 2 s offset is the pre-existing service-start delay between the controller's and the service's clocks). (b) resume continued from the frozen value each time (0:35→0:37→0:43, 1:11→1:16, 3:59→4:04); the estimate resumed accruing. (c) stop after ~17 min wall with ~8 min of pauses: the saved session duration is 7:54 — the ACTIVE time — and the session WAV was exactly the active time (372.0 s of PCM16 at the mid-check), proving no audio was captured or sent while paused; billed 226 s ($0.030), reflecting the audio the API processed on the final session. (d) 100 s and 300 s pauses: no reconnect loop while paused (one in-flight reconnect loop from a pre-pause VPN drop — the phone's WG Tunnel was reporting "Home Connection issue" — completed during the pause; no new reconnect was started while paused), and the resume continued the same session with the transcript intact; the reconnect machinery (×3, replays of 37.4 s / 168.0 s / 226.6 s of backlog) replayed all buffered audio seamlessly. The server did not idle-close the session during the 100 s/300 s pauses on this network, so the reconnect-on-resume path itself is covered by the unit tests rather than exercised on device.

## Workflow follow-up

- Review the change with the user; archive only after tests pass and the review is done.
- Archive the change, which syncs the delta specs into the main specs; verify the archived result with `openspec validate --strict` and `openspec list`.

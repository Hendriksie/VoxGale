# Battery Review — Phase 3 (wake lock + long screen-off sessions)

## What this reviews

The Phase 3 plan item "Wake-lock + battery review for long sessions": confirm the partial wake lock is actually held during screen-off capture (before this change the manifest lacked `WAKE_LOCK`, so the capture service's wake lock could never be acquired), and measure the battery cost of a long screen-off session to decide whether the risk table's "quality vs. battery" chunking setting (§8) is warranted.

## Off-device verification (done, 2026-10-27)

- `android.permission.WAKE_LOCK` is declared in `android/app/src/main/AndroidManifest.xml` and present in the built debug APK (`aapt dump badging`).
- `allowWakeLock: true` is set explicitly in `ForegroundTaskOptions` in `lib/main.dart`.
- `flutter_foreground_task` 11.0.3 acquires a `PARTIAL_WAKE_LOCK` (`ForegroundService:WakeLock`, reference-counting off) in `acquireLockMode()` while the service runs and releases it in `releaseLockMode()` when the service stops — the lock is held exactly for the session duration, matching the new `live-transcription` spec requirement (no wake lock when no session is active).

## On-device measurement (done, 2026-10-27 — Pixel 9 Pro XL, Android 15 / API 37, GrapheneOS)

Setup: debug APK installed; the app added to the doze whitelist (`dumpsys deviceidle whitelist +dev.hendriksie.voxtral_live`) so no battery-exemption prompt appeared and Doze could not interfere; phone discharging over ADB-USB (not charging); no other load.

- **Session:** 18:58:32 → 19:29:52 local (31:20 wall). Screen off from 18:58:35 to 19:29:03 (~30:28).
- **Capture continuity:** the session WAV grew at 32 kB/s (PCM16, 16 kHz, mono) for the entire session — 60,103,724 bytes ≈ 31:18 of audio at stop. The 30-minute screen-off session survived; the transcript streamed throughout.
- **Battery:** 68% at 18:58:32 → 65% at 19:28:49 (30:17 elapsed). **Drain: 3% ≈ 152 mAh ≈ ~300 mA average ≈ 5.9%/hour** screen-off (capture + continuous realtime WebSocket streaming + wake lock).
- **Wake lock:** `PARTIAL_WAKE_LOCK 'ForegroundService:WakeLock'` (uid 10306, our app) verified held at session start, mid-session, and at the 30-minute mark (`ACQ=-30m22s` at 19:28:49) with the screen off (`mWakefulness=Asleep`). After Stop: no `ForegroundService` wake lock and the FGS stopped — **released exactly when the session ended**, as the spec requires.
- **Foreground service:** microphone type (`0x80`), `isForeground=true` throughout; persistent notification present (channel `voxtral_live_capture`, `ONGOING_EVENT|NO_CLEAR|FOREGROUND_SERVICE`, Stop action).
- **Reconnect observation (bonus):** the realtime stream dropped once during the screen-off session and the Phase-1 reconnect path handled it — the status chip showed "Reconnected · Replayed 702.7 s" (buffered audio replayed into the re-established stream), the session continued seamlessly, and it saved to history. The API billed 702 s ($0.094) against a live estimate of $0.247: with a drop+replay, captured-but-unbilled audio makes the live estimate an **upper bound**. Cost-indicator note, not a defect.

## Recommendation

**Do not build the "quality vs. battery" chunking setting for v1.** At ≈ 6%/hour screen-off (~300 mA) on a flagship battery, a 2-hour session costs ≈ 12% — acceptable for an intentionally running transcription session where the user sees the persistent notification, elapsed time, and live cost estimate. The wake lock is held only while a session runs (verified released after stop), so idle drain is unaffected. Revisit if dogfooding on other devices (weaker radios, aggressive OEM battery management) shows materially worse drain, or if users report it.

## Related

- The audio-focus pause/resume (group 3) and the shared empty/error states (group 2) are covered by unit/widget tests; their on-device behavior was verified in the 6.3 smoke test (see `tasks.md`).
- Smoke-test findings that changed the implementation: (1) `record`'s internal focus request fought the audio-focus gateway — fixed with `audioInterruption: AudioInterruptionMode.none`; (2) the empty-transcript state now reads "No transcript yet." during a session instead of inviting to start one. Both are recorded in `design.md` (P3-D2, P3-D1) and the project KB gotchas.

# Battery Review — Phase 3 (wake lock + long screen-off sessions)

## What this reviews

The Phase 3 plan item "Wake-lock + battery review for long sessions": confirm the partial wake lock is actually held during screen-off capture (before this change the manifest lacked `WAKE_LOCK`, so the capture service's wake lock could never be acquired), and measure the battery cost of a long screen-off session to decide whether the risk table's "quality vs. battery" chunking setting (§8) is warranted.

## Off-device verification (done, 2026-10-27)

- `android.permission.WAKE_LOCK` is declared in `android/app/src/main/AndroidManifest.xml` and present in the built debug APK (`aapt dump badging`).
- `allowWakeLock: true` is set explicitly in `ForegroundTaskOptions` in `lib/main.dart`.
- `flutter_foreground_task` 11.0.3 acquires a `PARTIAL_WAKE_LOCK` (`ForegroundService:WakeLock`, reference-counting off) in `acquireLockMode()` while the service runs and releases it in `releaseLockMode()` when the service stops — the lock is held exactly for the session duration, matching the new `live-transcription` spec requirement (no wake lock when no session is active).
- Consequence: before this change the acquire could not succeed (no permission); screen-off sessions relied on the foreground service alone for CPU wakefulness. Now the wake lock engages.

## Measurement protocol (pending — requires a physical device)

Setup: physical Android device connected over adb (`~/Android/Sdk/platform-tools/adb`), the app installed from the debug APK (`build/app/outputs/flutter-apk/app-debug.apk`), battery ≥ 80%, the battery-optimization exemption granted (the app prompts for it at session start), no other heavy load on the device.

1. Record battery level and time: `adb shell dumpsys battery | grep level`.
2. Start a live session in the app, turn the screen off, let it run 30+ minutes.
3. During the session, verify the wake lock is held: `adb shell dumpsys power | grep -i wakelock` — expect `ForegroundService:WakeLock` (PARTIAL) held.
4. Stop the session; verify the lock is released (same `dumpsys power` — the lock is gone).
5. Record battery level and time again; compute the % drain and the %/hour rate.
6. Optional: repeat on a second day for a sanity range.

## Findings (pending device measurement)

- Battery before / after: _pending_
- Drain rate (%/hour, screen off, active capture + realtime streaming): _pending_
- Wake lock held during the session / released after stop: _pending on-device confirmation_ (statically verified above)

## Recommendation (pending)

This review feeds one decision: whether to build the "quality vs. battery" chunking setting from the risk table (§8). Once the numbers exist, record the recommendation here — if the screen-off drain rate is modest, the setting is not warranted for v1; if it is materially high, propose the chunking setting as a follow-up change.

## Related

- The audio-focus pause/resume (group 3) and the shared empty/error states (group 2) are covered by unit/widget tests; their on-device behavior is part of the 6.3 smoke test in `tasks.md`.
- The 6.3 smoke test also covers: a phone call mid-session (pause/resume), the wake-lock held/released check, and the on-device launcher-icon check.

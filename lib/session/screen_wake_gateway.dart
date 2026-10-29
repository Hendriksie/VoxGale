// The screen-wake seam (change 2026-10-29-keep-screen-on-during-sessions,
// design decision 1): the app's boundary to the platform's screen wake lock
// (FLAG_KEEP_SCREEN_ON on the activity window). `wakelock_plus` is a
// platform channel — it cannot run in unit tests — so the live session
// controller drives keep-screen-on through this interface and the tests
// inject a fake (the project's inject-a-seam rule). The production
// implementation wraps the wakelock_plus plugin.
//
// This is deliberately separate from the partial wake lock the capture
// foreground service holds while a session runs (flutter_foreground_task's
// allowWakeLock, live-transcription spec "Keep the device awake while
// capture is running"): that one keeps the CPU streaming with the screen
// off; this one keeps the display on while the app is foregrounded.

import 'package:wakelock_plus/wakelock_plus.dart';

/// The screen-wake seam: holds or releases the screen wake lock.
abstract interface class ScreenWakeGateway {
  /// Sets the screen wake lock: [on] keeps the display on while the app's
  /// window is visible; !on releases it. Idempotent.
  Future<void> setScreenOn(bool on);
}

/// [ScreenWakeGateway] backed by the wakelock_plus plugin (a platform
/// channel — never constructed in unit tests; the tests use a fake).
class WakelockPlusScreenWakeGateway implements ScreenWakeGateway {
  @override
  Future<void> setScreenOn(bool on) => WakelockPlus.toggle(enable: on);
}

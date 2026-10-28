import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/live_session_screen.dart';
import 'app/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Port for communication between the foreground task isolate and the UI.
  FlutterForegroundTask.initCommunicationPort();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'voxgale_capture',
      channelName: 'Live transcription',
      channelDescription: 'Shown while a live transcription session is active',
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      // Explicit (Phase 3): the capture service holds a partial wake lock
      // while a session runs, so streaming survives the screen being off.
      // Requires the WAKE_LOCK permission in the manifest.
      allowWakeLock: true,
    ),
  );

  runApp(const ProviderScope(child: VoxtralLiveApp()));
}

class VoxtralLiveApp extends StatelessWidget {
  const VoxtralLiveApp({super.key, this.themeMode});

  /// Overrides the theme mode (used by tests to exercise both themes).
  final ThemeMode? themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoxGale',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode ?? ThemeMode.system,
      // The live session screen is home (design P1-D6); the spike harness
      // and the debug-only API key entry live behind the debug-only route
      // opened from the live screen's app bar.
      home: const LiveSessionScreen(),
    );
  }
}

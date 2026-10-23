import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/home_screen.dart';
import 'app/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Port for communication between the foreground task isolate and the UI.
  FlutterForegroundTask.initCommunicationPort();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'voxtral_live_capture',
      channelName: 'Live transcription',
      channelDescription: 'Shown while a live transcription session is active',
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
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
      title: 'Voxtral Live',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode ?? ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
